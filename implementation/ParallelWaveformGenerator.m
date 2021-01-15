% This class provides all necessary functions for generating and decoding
% a waveform.

classdef ParallelWaveformGenerator
    methods (Static)
        
        % This method generates a waveform using parallel worker threads.
        function [waveform, unacknowledgedPacketsMap] = generateWaveform(config, waveformInd, seqNrOffset, packets, unacknowledgedPacketsMap, resendablePacketKeys)
            
            % Configuration for VHTWaveform
            VHTcfg = wlanVHTConfig;         % Create packet configuration
            VHTcfg.ChannelBandwidth = config.channelBandwidth;
            VHTcfg.MCS = config.MCS;                  % Modulation: e.g. 6 for 64QAM Rate: 2/3
            VHTcfg.NumTransmitAntennas = 1;   % Number of transmit antenna
            
            %Add pad zeros 
            packets = [packets; zeros(config.msduLength-mod(length(packets),config.msduLength),1)];
            
            % Generate waveform frames
            numMSDUs = ceil(length(packets)/config.msduLength);
            
            %Extract Payloads
            apepLengths = cell(numMSDUs, 1);
            frames = cell(numMSDUs, 1);
            newResults = cell(numMSDUs, 1);
            for ind=1:numMSDUs
                frames{ind} = packets((ind-1)*config.msduLength+1:config.msduLength*ind);
            end
            
            oldResults = cell(size(resendablePacketKeys, 2), 1);
            for ind=1:size(resendablePacketKeys, 2)
                waveformData = unacknowledgedPacketsMap(string(resendablePacketKeys(ind)));
                apepLengths{ind} = waveformData{1};
                oldResults{ind} = waveformData{2};
                oldSeqNrSplit = split(resendablePacketKeys(ind), 'I');
                unacknowledgedPacketsMap(string(strcat('W', num2str(waveformInd), 'I', oldSeqNrSplit{2}))) = oldResults{ind};
            end
            if(~isempty(resendablePacketKeys))
                remove(unacknowledgedPacketsMap, resendablePacketKeys);
            end
            
            parfor ind=1:numMSDUs
                [waveformFrame, apepLength] = WaveformUtils.generateWaveformFrame(frames{ind}, 1 + mod((seqNrOffset+ind-1), 4095), VHTcfg);
                apepLengths{ind} = apepLength;
                newResults{ind} = waveformFrame;
            end
            %cannot be done in parfor
            for ind=1:numMSDUs
                unacknowledgedPacketsMap(string(strcat('W', num2str(waveformInd), 'I', num2str(1 + mod((seqNrOffset+ind-1), 4095))))) = {apepLengths{ind} newResults{ind}};
            end
            VHTcfg.APEPLength = apepLengths{end};
            
            %merge results
            waveform = ParallelWaveformGenerator.mergeWaveform(config, VHTcfg, [oldResults; newResults]);
        end
        
        % This method merges all waveform frames together into a single waveform.
        function txWaveform = mergeWaveform(config, VHTcfg, waveformFrames)
            
            %Merge all WLANMACFrames together
            data = zeros(1, size(waveformFrames,1) * VHTcfg.PSDULength*8, 'int8');
            for ind=1:size(waveformFrames,1)
                data(1+(ind-1)*VHTcfg.PSDULength*8:ind*VHTcfg.PSDULength*8) = waveformFrames{ind}';
            end
            
            % Generate baseband VHT packets separated by idle time
            txWaveform = wlanWaveformGenerator(data',VHTcfg, 'NumPackets',size(waveformFrames,1), ...
                'IdleTime',config.idleTimeAfterEachPacket, ...
                'ScramblerInitialization',randi([1 127],size(waveformFrames,1),1));
            
            % Resample the transmit waveform at 30MHz
            fs = wlanSampleRate(VHTcfg); % Transmit sample rate in MHz
            osf = 1.5;                     % OverSampling factor
            
            txWaveform  = resample(txWaveform,fs*osf,fs);
            
            % Scale the normalized signal to avoid saturation of RF stages
            powerScaleFactor = 0.8;
            txWaveform = txWaveform.*(1/max(abs(txWaveform))*powerScaleFactor);
        end
        
        % This method decodes a given waveform using parallel worker threads.
        function [packets, packetSeqNrs] = decodeWaveform(config, waveform)
            
            %Extract parameters        
            VHTcfg = wlanVHTConfig;         
            VHTcfg.ChannelBandwidth = config.channelBandwidth;
            VHTcfg.MCS = config.MCS;                 
            sr = wlanSampleRate(VHTcfg);                             
            
            chanBW = VHTcfg.ChannelBandwidth;
            indLSTF = wlanFieldIndices(VHTcfg,'L-STF');
            indLSIG = wlanFieldIndices(VHTcfg,'L-SIG');
            indSIGA = wlanFieldIndices(VHTcfg, 'VHT-SIG-A');
            Ns = indLSIG(2)-indLSIG(1)+1;
            
            % Downsample the received signal
            waveform = resample(waveform,sr,sr*config.oversamplingFactor);
            rxWaveformLen = size(waveform,1);
            
            % Minimum packet length is 10 OFDM symbols
            lstfLen = double(indLSTF(2)); % Number of samples in L-STF
            minPktLen = lstfLen*5;
            
            % Receiver processing
            threads = [];
            packets = {};
            finishedSeqNrs = zeros(0, 0, 'int16');
            duplicateSequenceNrDetected = 0;
            
            %Get SequenceNr from finished Threads and abort all
            %following threads if the sequenceNr is not unique
            sequenceNrQueue = parallel.pool.DataQueue;
            afterEach(sequenceNrQueue, @checkForDuplicateSeqNr);
            
            function checkForDuplicateSeqNr(input)
                if ~exist('finishedSeqNrs','var')
                    return;
                end
                curPktInd = input(1);
                seqNr = input(2);
                if ismember(seqNr, finishedSeqNrs)
                    duplicateSequenceNrDetected = 1;
                end
                finishedSeqNrs(curPktInd) = seqNr;
            end
            
            pktInd = 1;
            searchOffset = 0;
            while ~duplicateSequenceNrDetected && (searchOffset + minPktLen) <= rxWaveformLen 
                % Packet detect
                pktOffset = wlanPacketDetect(waveform, chanBW, searchOffset, 0.8);
                
                % Adjust packet offset
                pktOffset = searchOffset+pktOffset;
                if isempty(pktOffset) || (pktOffset+indLSIG(2)>rxWaveformLen)
                    break;
                end
                
                [pktOffset, coarseFreqOffset] = WaveformUtils.adjustPacketOffset(waveform(pktOffset + (indLSTF(1):indLSIG(2)), :), pktOffset, chanBW, sr);
                
                % Check if packet was successfully detected
                if (pktOffset<0) || ((pktOffset+minPktLen)>rxWaveformLen)
                    searchOffset = pktOffset+1.5*lstfLen;
                    continue;
                end
                
                if (pktOffset + minPktLen) > rxWaveformLen
                    searchOffset = pktOffset+1.5*lstfLen;
                    continue;
                end

                % Timing synchronization complete: packet detected
                [fmt, noiseVarNonHT, demodLLTF, chanEstLLTF, rxLSIG] = WaveformUtils.detectFormat(VHTcfg, helperFrequencyOffset(waveform(pktOffset+(1:7*Ns),:),sr,-coarseFreqOffset), chanBW, sr);
                
                if ~strcmp(fmt,'VHT')
                    searchOffset = pktOffset+1.5*lstfLen;
                    continue;
                end
                
                % Recover L-SIG field bits
                [rxLSIGBits, failCheck, ~] = wlanLSIGRecover(rxLSIG, chanEstLLTF, noiseVarNonHT, chanBW);

                if failCheck % Skip L-STF length of samples and continue searching
                    searchOffset = pktOffset+1.5*lstfLen;
                    continue;
                end
                
                % Recover VHT-SIG-A field bits
                [rxSIGABits, failCRC, ~] = wlanVHTSIGARecover(waveform(pktOffset + (indSIGA(1):indSIGA(2)), :), ...
                    chanEstLLTF, noiseVarNonHT, chanBW);

                if failCRC
                    searchOffset = pktOffset+1.5*lstfLen;
                    continue;
                end

                % Create a VHT format configuration object by retrieving packet parameters
                % from the decoded L-SIG and VHT-SIG-A bits
                cfgVHTRx = helperVHTConfigRecover(rxLSIGBits, rxSIGABits);
                
                % Obtain starting and ending indices for VHT-LTF and VHT-Data fields
                % using retrieved packet parameters
                indVHTLTF  = wlanFieldIndices(cfgVHTRx, 'VHT-LTF');
                indVHTSIGB = wlanFieldIndices(cfgVHTRx, 'VHT-SIG-B');
                indVHTData = wlanFieldIndices(cfgVHTRx, 'VHT-Data');

                % Warn if waveform does not contain whole packet
                if (pktOffset + double(indVHTData(2))) > rxWaveformLen
                    searchOffset = pktOffset+1.5*lstfLen;
                    continue;
                end
                
                % Estimate MIMO channel using VHT-LTF and retrieved packet parameters
                demodVHTLTF = wlanVHTLTFDemodulate(waveform(pktOffset + (indVHTLTF(1):indVHTLTF(2)), :), cfgVHTRx);
                chanEstVHTLTF = wlanVHTLTFChannelEstimate(demodVHTLTF, cfgVHTRx);

                % Estimate noise power in VHT-SIG-B fields
                noiseVarVHT = helperNoiseEstimate(demodLLTF, chanBW, cfgVHTRx.NumSpaceTimeStreams);

                % VHT-SIG-B Recover
                [rxSIGBBits, ~] = wlanVHTSIGBRecover(waveform(pktOffset + (indVHTSIGB(1):indVHTSIGB(2)),:), ...
                    chanEstVHTLTF, noiseVarVHT, chanBW);

                % Interpret VHT-SIG-B bits to recover the APEP length (rounded up to a
                % multiple of four bytes) and generate reference CRC bits
                [refSIGBCRC, ~] = helperInterpretSIGB(rxSIGBBits, chanBW, true);
                
                t = parfeval(@ParallelWaveformGenerator.decodePacket, 2, cfgVHTRx, sequenceNrQueue, pktInd, waveform(pktOffset + (indVHTData(1):indVHTData(2)), :), refSIGBCRC, vhtSingleStreamChannelEstimate(demodVHTLTF, cfgVHTRx), chanEstVHTLTF);
                threads = [threads t];  %#ok<*AGROW>
                
                % Update search index
                searchOffset = pktOffset+double(indVHTData(2));
                pktInd = pktInd+1;           
            end
            
            %retrieve data and cancel all unnecessary threads
            packetSeqNrs = zeros(1, size(threads, 2), 'int16');
            doneCollecting = 0;
            for ind = 1:size(threads, 2)
                if(~doneCollecting)
                    [packet, packetSeqNr] = fetchOutputs(threads(ind));
                    
                    if isempty(packet)
                        continue;
                    end
                   
                    if (ismember(packetSeqNr, packetSeqNrs))
                        doneCollecting = 1;
                        continue;
                    end
                    packets{packetSeqNr} = packet;
                    packetSeqNrs(ind) = packetSeqNr;
                else
                    cancel(threads(ind));
                end
            end
            packetSeqNrs = nonzeros(packetSeqNrs)';
            clear threads;
        end
        
        % This method decodes a single waveform packet.
        function [packet, packetSeqNr] = decodePacket(cfgVHTRx, sequenceNrQueue, pktInd, vhtdata, refSIGBCRC, chanEstSSPilots, chanEstVHTLTF)
            packet = zeros(0,1);
            packetSeqNr = -1;
            
            % Estimate the noise power in VHT data field
            noiseVarVHT = vhtNoiseEstimate(vhtdata, chanEstSSPilots, cfgVHTRx);

            % Recover PSDU bits using retrieved packet parameters and channel
            % estimates from VHT-LTF
            [rxPSDU, rxSIGBCRC, ~] = wlanVHTDataRecover(vhtdata, chanEstVHTLTF, noiseVarVHT, cfgVHTRx);

            % Test VHT-SIG-B CRC from service bits within VHT Data against
            % reference calculated with VHT-SIG-B bits
            if ~isequal(refSIGBCRC, rxSIGBCRC)
                return;
            end

            mpduList = wlanAMPDUDeaggregate(rxPSDU, cfgVHTRx);

            packetSeq = zeros(1, numel(mpduList), 'int16');
            for i = 1:numel(mpduList)
                [macCfg, payload, decodeStatus] = wlanMPDUDecode(mpduList{i}, cfgVHTRx, ...
                                                                'DataFormat', 'octets');
                if ~strcmp(decodeStatus, 'FCSFailed')
                    % Store sequencing information
                    packetSeqNr = macCfg.SequenceNumber;
                    send(sequenceNrQueue, [pktInd, packetSeqNr]);
                    packetSeq(i) = packetSeqNr;
                    
                    % Convert MSDU to a binary data stream
                    packet = reshape(hex2dec(payload)', [], 1); 

                    % Finish processing when a duplicate packet is detected. The
                    % recovered data includes bits from duplicate frame
                    if length(unique(packetSeq))<length(packetSeq)
                        break;
                    end
                end
            end
        end
    end
end