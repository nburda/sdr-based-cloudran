% This class provides all necessary functions for the tcpip connection to the server and
% client instances.

classdef TCPIPConnection
    methods (Static)
        
        % This method creates a TCPIP socket with the given arguments.
        function tcpIpSocket = createTcpIpSocket(ipAdress, port, isServer, capacity)
            if isServer
                tcpIpSocket = tcpip(ipAdress, port, 'NetworkRole', 'server', 'Timeout', 0.1);
                CloudRANUtils.dispMessage("Waiting for Connection on " + ipAdress + ":" + int2str(port));
            else
                pause(0.5);
                tcpIpSocket = tcpip(ipAdress, port, 'NetworkRole', 'client', 'Timeout', 0.1);
            end
            
            if exist('capacity', 'var')
                tcpIpSocket.InputBufferSize = capacity;
                tcpIpSocket.OutputBufferSize = capacity;
            end
            
            try
                fopen(tcpIpSocket);
            catch
                error(strcat("ERROR: Could not start TCP-IP Socket on ", ipAdress, ...
                    ":", int2str(port), " !"));
            end

            CloudRANUtils.dispMessage("Connected to " + ipAdress + ":" + int2str(port));
        end
        
        % This method extracts all sendable packets and sends them via the tcpIpClient.
        % All decoded but not sendable packets are saved within a Map.
        function [expectedStartSeqNr, previouslyRemaingingPackets, bytesProcessed] = extractAndSendData(cloudranConfig, sdrConfig, tcpIpClient, expectedStartSeqNr, receivedSeqNrs, receivedPackets, previouslyRemaingingPackets)
            sendableSeqNrs = CloudRANUtils.getFirstSequence(expectedStartSeqNr, receivedSeqNrs);
            dataToSend = zeros(1,size(sendableSeqNrs, 2)*sdrConfig.msduLength, 'int8');
            for x=1:size(sendableSeqNrs, 2)
                dataToSend(1+(x-1)*sdrConfig.msduLength:x*sdrConfig.msduLength) = receivedPackets{sendableSeqNrs(x)}';
            end
            dataToSend = nonzeros(dataToSend);
            bytesProcessed = size(dataToSend, 1);
            if(~isempty(sendableSeqNrs) && expectedStartSeqNr == sendableSeqNrs(1))
                expectedStartSeqNr = mod(sendableSeqNrs(end), 4095)+1;
                TCPIPConnection.sendDataFromTcpIpClient(tcpIpClient, dataToSend);
                remainingPacketSeqNrs = cell2mat(keys(previouslyRemaingingPackets));
                for ind=1:size(sendableSeqNrs, 2)
                    if(ismember(sendableSeqNrs(ind), remainingPacketSeqNrs))
                        remove(previouslyRemaingingPackets, sendableSeqNrs(ind));
                    end
                end
            else
                sendableSeqNrs = [];
            end
            receivedSeqNrs = setdiff(receivedSeqNrs, sendableSeqNrs);
            if(cloudranConfig.selectiveAck && ~isempty(receivedPackets))
                for x=1:size(receivedSeqNrs, 2)
                    previouslyRemaingingPackets(receivedSeqNrs(x)) = receivedPackets{receivedSeqNrs(x)};
                end 
            end
        end
        
        % This method sends the given data via a given tcpIpClient.
        function sendDataFromTcpIpClient(tcpIpClient, data)
            CloudRANUtils.dispMessage("Sending Data ... ");
            while ~isempty(data)
                fwrite(tcpIpClient, data(1:min(tcpIpClient.OutputBufferSize, size(data, 1))));
                data(1:min(tcpIpClient.OutputBufferSize, size(data, 1))) = [];
            end
        end
        
        % This method receives data from a given tcpIpServer and saves it in
        % receiverAsyncBuffer.
        function receiverAsyncBuffer = getDataFromTcpIpServer( ...
                connectionTimeout, tcpIpServer, receiverAsyncBuffer)
            
            curTCPIPConnectionTimeOut = 0;
            while strcmp(tcpIpServer.Status, 'open') && ...
                    curTCPIPConnectionTimeOut < connectionTimeout
                if tcpIpServer.BytesAvailable == 0
                    curTCPIPConnectionTimeOut = curTCPIPConnectionTimeOut+1;
                    pause(0.01);
                    continue;
                end

                curTCPIPConnectionTimeOut = 0;
                
                tcpIpData = fread(tcpIpServer, double(min(tcpIpServer.BytesAvailable, ...
                    (receiverAsyncBuffer.Capacity - receiverAsyncBuffer.NumUnreadSamples))));
                write(receiverAsyncBuffer,tcpIpData);

                %Check if Buffer is full
                if receiverAsyncBuffer.NumUnreadSamples == receiverAsyncBuffer.Capacity
                    return;
                end
            end
        end
    end
end