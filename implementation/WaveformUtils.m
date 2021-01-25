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
            
            % Detect the format of the packet
            try 
                %disable warnings for failed L-SIG checks since missing
                %packets should occur in a realistic transmission
                warning('off','all');
                fmt = wlanFormatDetect(vht((indLSIG(1):indSIGA(2)), :), ...
                    chanEstLLTF, noiseVarNonHT, chanBW);
                warning('on','all');
            catch
                fmt = 'Null';
            end
        end
    end
end