% This class provides all necessary functions for generating and decoding
% a waveform.

classdef WaveformUtils
    methods (Static) 
        % This method generates a waveform frame for the given data.
        function [waveformFrame, apepLength] = generateWaveformFrame(data, seqNum, VHTcfg)    

            % Create MAC frame configuration object and configure sequence number
            cfgMAC = wlanMACFrameConfig('FrameType', 'QoS Data', 'SequenceNumber', seqNum);
            cfgMAC.FrameFormat = 'VHT';

            % Generate MPDU
            [waveformFrame, apepLength] = wlanMACFrame(data, cfgMAC, VHTcfg, 'OutputFormat', 'bits');
        end
        
        % This method adjusts the packet offset using a coarse frequency
        % estimation.
        function [pktOffset, coarseFreqOffset] = adjustPacketOffset(LSTF, pktOffset, chanBW, sr)
            
            % Coarse frequency offset estimation using L-STF
            coarseFreqOffset = wlanCoarseCFOEstimate(LSTF, chanBW);

            % Coarse frequency offset compensation
            LSTF = helperFrequencyOffset(LSTF,sr,-coarseFreqOffset);

            % Symbol timing synchronization
            pktOffset = pktOffset+wlanSymbolTimingEstimate(LSTF,chanBW);
        end
        
        % This method detects the format of the given packet.
        function [fmt, noiseVarNonHT, demodLLTF, chanEstLLTF, rxLSIG] = detectFormat(VHTcfg, vht, chanBW, sr)

            indLLTF = wlanFieldIndices(VHTcfg,'L-LTF');
            indLSIG = wlanFieldIndices(VHTcfg,'L-SIG');
            indSIGA = wlanFieldIndices(VHTcfg, 'VHT-SIG-A');
            
            % Fine frequency offset estimation using L-LTF
            LLTF = vht((indLLTF(1):indLLTF(2)), :);
            fineFreqOffset = wlanFineCFOEstimate(LLTF, chanBW);

            % Fine frequency offset compensation
            vht = helperFrequencyOffset(vht, sr, -fineFreqOffset);

            % Channel estimation using L-LTF
            demodLLTF = wlanLLTFDemodulate(LLTF, chanBW);
            chanEstLLTF = wlanLLTFChannelEstimate(demodLLTF, chanBW);

            % Estimate noise power in non-HT fields
            noiseVarNonHT = helperNoiseEstimate(demodLLTF);

            rxLSIG = vht((indLSIG(1):indLSIG(2)), :);
            
            %disable warnings for failed L-SIG checks since missing
            %packets should occur in a realistic transmission
            warning('off','all')
            % Detect the format of the packet
            try 
                fmt = wlanFormatDetect(vht((indLSIG(1):indSIGA(2)), :), ...
                    chanEstLLTF, noiseVarNonHT, chanBW);
            catch
                fmt = 'Null';
            end
            warning('on','all')
        end
        
        % This method recovers the packet data from a given packet.
        function [rxPSDU, rxSIGBCRC, refSIGBCRC] = recoverPacketData(cfgVHTRx, rxWaveform, pktOffset, demodLLTF, chanBW)
            % Obtain starting and ending indices for VHT-LTF and VHT-Data fields
            % using retrieved packet parameters
            indVHTLTF  = wlanFieldIndices(cfgVHTRx, 'VHT-LTF');
            indVHTSIGB = wlanFieldIndices(cfgVHTRx, 'VHT-SIG-B');
            indVHTData = wlanFieldIndices(cfgVHTRx, 'VHT-Data');
            
            % Estimate MIMO channel using VHT-LTF and retrieved packet parameters
            demodVHTLTF = wlanVHTLTFDemodulate(rxWaveform(pktOffset + (indVHTLTF(1):indVHTLTF(2)), :), cfgVHTRx);
            chanEstVHTLTF = wlanVHTLTFChannelEstimate(demodVHTLTF, cfgVHTRx);

            % Estimate noise power in VHT-SIG-B fields
            noiseVarVHT = helperNoiseEstimate(demodLLTF, chanBW, cfgVHTRx.NumSpaceTimeStreams);

            % VHT-SIG-B Recover
            [rxSIGBBits, ~] = wlanVHTSIGBRecover(rxWaveform(pktOffset + (indVHTSIGB(1):indVHTSIGB(2)),:), ...
                chanEstVHTLTF, noiseVarVHT, chanBW);

            % Interpret VHT-SIG-B bits to recover the APEP length (rounded up to a
            % multiple of four bytes) and generate reference CRC bits
            [refSIGBCRC, ~] = helperInterpretSIGB(rxSIGBBits, chanBW, true);

            % Get single stream channel estimate
            chanEstSSPilots = vhtSingleStreamChannelEstimate(demodVHTLTF, cfgVHTRx);

            % Extract VHT Data samples from the waveform
            vhtdata = rxWaveform(pktOffset + (indVHTData(1):indVHTData(2)), :);

            % Estimate the noise power in VHT data field
            noiseVarVHT = vhtNoiseEstimate(vhtdata, chanEstSSPilots, cfgVHTRx);

            % Recover PSDU bits using retrieved packet parameters and channel
            % estimates from VHT-LTF
            [rxPSDU, rxSIGBCRC, ~] = wlanVHTDataRecover(vhtdata, chanEstVHTLTF, noiseVarVHT, cfgVHTRx);
        end
    end
end