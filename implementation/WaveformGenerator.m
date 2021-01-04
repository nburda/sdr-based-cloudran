% This class provides all necessary functions for generating and decoding
% a waveform.

classdef WaveformGenerator
    methods (Static)       
        
        % Generate a waveform from the given packets.
        function [txWaveform, unacknowledgedPacketsMap] = generateWaveform(config, waveformInd,  seqNrOffset, packets, unacknowledgedPacketsMap, resendablePacketKeys)            
            
            VHTcfg = wlanVHTConfig;
            VHTcfg.ChannelBandwidth = config.channelBandwidth;
            VHTcfg.MCS = config.MCS;
            VHTcfg.NumTransmitAntennas = 1;
            
            app_payload_sz = size(packets,1);
            
            numMSDUs = ceil(length(packets)/config.msduLength);
            
            packets = [packets; zeros(config.msduLength-mod(length(packets),config.msduLength),1)];
            
            % Divide input data stream into fragments (frames)
            data = zeros(0, 0, 'int8');
            
            % size on MAC layer
            mpdu_payload_sz = 0;
            
            %Get previous Packets
            oldResults = zeros(0, 0, 'int8');
            for ind=1:size(resendablePacketKeys, 2)
                waveformData = unacknowledgedPacketsMap(string(resendablePacketKeys(ind)));
                VHTcfg.APEPLength  = waveformData{1};
                oldResults = [oldResults; waveformData{2}];
                oldSeqNrSplit = split(resendablePacketKeys(ind), 'I');
                unacknowledgedPacketsMap(string(strcat('W', num2str(waveformInd), 'I', oldSeqNrSplit{2}))) = unacknowledgedPacketsMap(string(resendablePacketKeys(ind)));
            end
            if(~isempty(resendablePacketKeys))
                remove(unacknowledgedPacketsMap, resendablePacketKeys);
            end
            
            for ind=1:numMSDUs
                % Extract data (in octets) for each MPDU
                frameBody = packets((ind-1)*config.msduLength+1:config.msduLength*ind,:);
                
                % Create MAC frame configuration object and configure sequence number
                seqNr = 1 + mod((seqNrOffset+ind-1), 4095);
                [waveformFrame, apepLength] = WaveformUtils.generateWaveformFrame(frameBody, seqNr, VHTcfg);
                
                VHTcfg.APEPLength  = apepLength;   % Set the APEP length
                
                % Concatenate PSDUs for waveform generation
                data = [data; waveformFrame]; %#ok<*AGROW>
                unacknowledgedPacketsMap(string(strcat('W', num2str(waveformInd), 'I', num2str(seqNr)))) = {apepLength, waveformFrame};
                
                mpdu_payload_sz = mpdu_payload_sz + apepLength;
            end
            
            data = [oldResults; data];
            
            CloudRANUtils.dispMessage("Size on MAC layer: " + mpdu_payload_sz + " Bytes, " + (mpdu_payload_sz/app_payload_sz) + " x app");
            % Initialize the scrambler with a random integer for each packet
            numMSDUs = numMSDUs + floor(size(oldResults,1)/(config.msduLength*8));
            
            % Generate baseband VHT packets separated by idle time
            txWaveform = wlanWaveformGenerator(data, VHTcfg, 'NumPackets',numMSDUs, ...
                'IdleTime',config.idleTimeAfterEachPacket, ...
                'ScramblerInitialization',randi([1 127],numMSDUs,1));
            
            bb_waveform_sz = size(txWaveform,1) * 4;
            CloudRANUtils.dispMessage("Size on PHY layer (BB): " + bb_waveform_sz + " Bytes, " + (bb_waveform_sz/app_payload_sz) + " x app");
            
            % Resample the transmit waveform at 30MHz
            sr = wlanSampleRate(VHTcfg); % Transmit sample rate in MHz
            osf = 1.5;                     % OverSampling factor
            
            txWaveform  = resample(txWaveform,sr*osf,sr);
            
            bb_res_waveform_sz = size(txWaveform,1) * 4;
            CloudRANUtils.dispMessage("Size on PHY layer (resampled BB): " + bb_res_waveform_sz + " Bytes, " + (bb_res_waveform_sz/app_payload_sz) + " x app");
            
            time = ((0:length(txWaveform)-1)/(sr*osf))*1e6;
            
            if (config.GUI)
                plot(time, abs(txWaveform))
                xlabel ('Time (microseconds)');
                ylabel('Magnitude');
            end
            
            waveform_duration_sec = max(time) / 1e6;
            waveform_data_rate = bb_res_waveform_sz * (1/waveform_duration_sec) * 8;
            
            CloudRANUtils.dispMessage("Generated WLAN transmit waveform of " + waveform_duration_sec + " sec, rate " + waveform_data_rate/1e9 + " Gbps");
            
            % Scale the normalized signal to avoid saturation of RF stages
            powerScaleFactor = 0.8;
            txWaveform = txWaveform.*(1/max(abs(txWaveform))*powerScaleFactor);
        end        
        
        %Decode the given waveform and return the resulting ipPacket.
        function [packets, packetSeq] = decodeWaveform(config, rxWaveform)
  
            VHTcfg = wlanVHTConfig;         % Create packet configuration
            VHTcfg.MCS = config.MCS;
            VHTcfg.ChannelBandwidth = config.channelBandwidth;

            chanBW = VHTcfg.ChannelBandwidth;
            indLSTF = wlanFieldIndices(VHTcfg,'L-STF');
            indLSIG = wlanFieldIndices(VHTcfg,'L-SIG');
            indSIGA = wlanFieldIndices(VHTcfg, 'VHT-SIG-A');
            Ns = indLSIG(2)-indLSIG(1)+1;
            
            % Downsample the received signal
            sr = wlanSampleRate(VHTcfg); % Sampling rate
            rxWaveform = resample(rxWaveform,sr,sr*config.oversamplingFactor);
            
            % Minimum packet length is 10 OFDM symbols
            lstfLen = double(indLSTF(2)); % Number of samples in L-STF
            minPktLen = lstfLen*5;
            pktInd = 1;
            rxWaveformLen = size(rxWaveform,1);
            packetSeq = zeros(0, 0, 'int16');
            
            % Receiver processing
            packets = {};
            searchOffset = 0;
            while (searchOffset + minPktLen) <= rxWaveformLen
                % Packet detect
                pktOffset = wlanPacketDetect(rxWaveform, chanBW, searchOffset, 0.8);
                
                % Adjust packet offset
                pktOffset = searchOffset+pktOffset;
                if isempty(pktOffset) || (pktOffset+indLSIG(2)>rxWaveformLen)
                    if pktInd==1
                        CloudRANUtils.dispMessage("** No packet detected **");
                    end
                    break;
                end
                
                [pktOffset, coarseFreqOffset] = WaveformUtils.adjustPacketOffset(rxWaveform(pktOffset + (indLSTF(1):indLSIG(2)), :), pktOffset, chanBW, sr);
                
                % Check if packet was successfully detected
                if (pktOffset<0) || ((pktOffset+minPktLen)>rxWaveformLen)
                    searchOffset = pktOffset+1.5*lstfLen;
                    continue;
                end
                
                if (pktOffset + minPktLen) > rxWaveformLen
                    CloudRANUtils.dispMessage("** Not enough samples to recover packet **");
                    searchOffset = pktOffset+1.5*lstfLen;
                    continue;
                end

                % Timing synchronization complete: packet detected
                CloudRANUtils.dispMessage("Packet detected at index " + pktOffset);
                [fmt, noiseVarNonHT, demodLLTF, chanEstLLTF, rxLSIG] = WaveformUtils.detectFormat(VHTcfg, helperFrequencyOffset(rxWaveform(pktOffset+(1:7*Ns),:),sr,-coarseFreqOffset), chanBW, sr);
                
                if ~strcmp(fmt,'VHT')
                    CloudRANUtils.dispMessage("A format other than VHT has been detected");
                    searchOffset = pktOffset+1.5*lstfLen;
                    continue;
                end
                
                % Recover L-SIG field bits
                CloudRANUtils.dispMessage("Decoding L-SIG... ");
                [rxLSIGBits, failCheck, ~] = wlanLSIGRecover(rxLSIG, chanEstLLTF, noiseVarNonHT, chanBW);

                if failCheck % Skip L-STF length of samples and continue searching
                    CloudRANUtils.dispMessage("** L-SIG check fail **");
                    searchOffset = pktOffset+1.5*lstfLen;
                    continue;
                else
                    CloudRANUtils.dispMessage("L-SIG check pass");
                end
                
                % Recover VHT-SIG-A field bits
                CloudRANUtils.dispMessage("Decoding VHT-SIG-A... ");
                [rxSIGABits, failCRC, ~] = wlanVHTSIGARecover(rxWaveform(pktOffset + (indSIGA(1):indSIGA(2)), :), chanEstLLTF, noiseVarNonHT, chanBW);

                if failCRC
                    CloudRANUtils.dispMessage("** VHT-SIG-A CRC fail **");
                    searchOffset = pktOffset+1.5*lstfLen;
                    continue;
                else
                    CloudRANUtils.dispMessage("VHT-SIG-A CRC pass");
                end

                % Create a VHT format configuration object by retrieving packet parameters
                % from the decoded L-SIG and VHT-SIG-A bits
                cfgVHTRx = helperVHTConfigRecover(rxLSIGBits, rxSIGABits);
                
                % Obtain starting and ending indices for VHT-Data fields
                % using retrieved packet parameters
                indVHTData = wlanFieldIndices(cfgVHTRx, 'VHT-Data');

                % Warn if waveform does not contain whole packet
                if (pktOffset + double(indVHTData(2))) > rxWaveformLen
                    CloudRANUtils.dispMessage("** Not enough samples to recover entire packet **");
                    searchOffset = pktOffset+1.5*lstfLen;
                    continue;
                end
                
                [rxPSDU, rxSIGBCRC, refSIGBCRC] = WaveformUtils.recoverPacketData(cfgVHTRx, rxWaveform, pktOffset, demodLLTF, chanBW);
                
                % Test VHT-SIG-B CRC from service bits within VHT Data against
                % reference calculated with VHT-SIG-B bits
                if ~isequal(refSIGBCRC, rxSIGBCRC)
                    CloudRANUtils.dispMessage("** VHT-SIG-B CRC fail **");
                    searchOffset = pktOffset+1.5*lstfLen;
                    continue;
                else
                    CloudRANUtils.dispMessage("VHT-SIG-B CRC pass");
                end
                
                mpduList = wlanAMPDUDeaggregate(rxPSDU, cfgVHTRx);
                CloudRANUtils.dispMessage("Number of MPDUs present in the A-MPDU: " + numel(mpduList));
                
                for i = 1:numel(mpduList)
                    [macCfg, payload, decodeStatus] = wlanMPDUDecode(mpduList{i}, cfgVHTRx, ...
                                                                    'DataFormat', 'octets');
                    if strcmp(decodeStatus, 'FCSFailed')
                        CloudRANUtils.dispMessage("** FCS failed for MPDU-" + i + " **");      
                    else
                        CloudRANUtils.dispMessage("FCS passed for MPDU-" + i);
                        
                        % Store sequencing information
                        packetSeq = [packetSeq macCfg.SequenceNumber];
                        
                        % Convert MSDU to a binary data stream
                        packets{macCfg.SequenceNumber} = reshape(hex2dec(payload)', [], 1); 

                        % Finish processing when a duplicate packet is detected. The
                        % recovered data includes bits from duplicate frame
                        if length(unique(packetSeq))<length(packetSeq)
                            break;
                        end
                        
                        % Display decoded information
                        if config.displayFlag
                             CloudRANUtils.dispMessage("  Decoded MAC Sequence Control field contents:");
                             CloudRANUtils.dispMessage("    Sequence number:" + macCfg.SequenceNumber);
                        end
                    end
                end
                
                % Finish processing when a duplicate packet is detected. The
                % recovered data includes bits from duplicate frame
                if length(unique(packetSeq))<length(packetSeq)
                    break;
                end
                
                % Update search index
                searchOffset = pktOffset+double(indVHTData(2));
                pktInd = pktInd+1;
            end
            
            packetSeq = unique(packetSeq);
        end
    end
end