% This class provides SoftwareFlowControl functionality for the CloudRAN.

classdef SoftwareFlowControl
    methods (Static)    
        
        %Sends an out of band blockacknowledgement containing the given sequencenumbers.
        function sendSignal(tcpIpSender, signal, waveformInds, seqNrs)
            if exist('waveformInds', 'var') && exist('seqNrs', 'var')
                fwrite(tcpIpSender, num2str([signal -1 waveformInds -1 seqNrs]), 'char');
            else
                fwrite(tcpIpSender, num2str(signal), 'char');
            end
        end
        
        %Waits until a signal is received via tcpip.
        function [signal, waveformInds, seqNrs] = waitForSignal(tcpIpReceiver)
            while 1
                if tcpIpReceiver.BytesAvailable ~= 0
                    break;
                end
            end
            warning('off','all')
            payload = char(fread(tcpIpReceiver, tcpIpReceiver.BytesAvailable, 'char')); %#ok<FREAD>
            warning('on','all')
            data = strsplit(num2str(payload'), '-1');
            signal = str2double(data{1});
            waveformInds = zeros(0,0,'int16');
            seqNrs = zeros(0, 0, 'int16');
            if(size(data, 2) > 1 && isnumeric(str2num(data{2})) && ~isempty(str2num(data{2})))
                waveformInds = str2num(data{2}); %#ok<*ST2NM>
                for ind=3:size(data, 2)
                    if(~isempty(num2str(str2num(data{ind})')))
                        seqNrs = [seqNrs strrep(string(strcat('W', num2str(waveformInds(ind-2)), 'I', num2str(str2num(data{ind})'))), ' ', '')'];
                    end
                end
            end
        end
    end
end