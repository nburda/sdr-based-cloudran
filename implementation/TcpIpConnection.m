% This class provides all necessary functions for the tcpip connection to the server and
% client instances.

classdef TcpIpConnection
    methods (Static)
        
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
        
        %Extracts all sendable Packets and sends them via the tcpIpClient.
        %All decoded by not sendable Packets are saved within a Map.
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
                TcpIpConnection.sendDataFromTcpIpClient(tcpIpClient, dataToSend);
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
        
        % Send data to tcpIpClientIP:tcpIpClientPort.
        function sendDataFromTcpIpClient(tcpIpClient, data)
            CloudRANUtils.dispMessage("Sending Data ... ");
            while ~isempty(data)
                fwrite(tcpIpClient, data(1:min(tcpIpClient.OutputBufferSize, size(data, 1))));
                data(1:min(tcpIpClient.OutputBufferSize, size(data, 1))) = [];
            end
        end
        
        % Receive data from tcpIpServerIP:tcpIpServerPort and save it in
        % receiverAsyncBuffer.
        function receiverAsyncBuffer = getDataFromTcpIpServer( ...
                connectionTimeout, tcpIpServer, receiverAsyncBuffer)
            
            curTcpIpConnectionTimeOut = 0;
            while strcmp(tcpIpServer.Status, 'open') && ...
                    curTcpIpConnectionTimeOut < connectionTimeout
                if tcpIpServer.BytesAvailable == 0
                    curTcpIpConnectionTimeOut = curTcpIpConnectionTimeOut+1;
                    pause(0.01);
                    continue;
                end

                curTcpIpConnectionTimeOut = 0;
                
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