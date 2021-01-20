% This is the main class for the cloudran, which sends data from a server
% via SDRs to a client.

classdef CloudRAN
    properties (Constant)
        XOFF = 17
        NOMOREDATA = 18;
        XON = 19
        TRANSMISSIONEND = 20
    end
    methods (Static)      
        % This method starts the CloudRAN Sender, which receives data from a Server via 
        % TCPIP and sends it to the SDR. 
        function startSender()
            
            clear;
            
            %Configuration file path
            configPath = "./config/senderconfig.conf";
            CloudRANUtils.showConfiguration(configPath)
            
            %Read configuration values
            cloudranConfig = CloudRANConfiguration.readConfigValues(configPath);
            sdrConfig = SDRConfiguration.readConfigValues(configPath);
            tcpIpConfig = TCPIPConfiguration.readConfigValues(configPath);
            
            %Create or Shutdown parpool if needed
            if ((~cloudranConfig.parallelGeneration && ~isempty(gcp('nocreate'))) || ...
                    (cloudranConfig.parallelGeneration && ~isempty(gcp('nocreate')) && gcp('nocreate').NumWorkers ~= cloudranConfig.parallelThreads))
                delete(gcp('nocreate'))
            end
            if (cloudranConfig.parallelGeneration && isempty(gcp('nocreate')))
                parpool(cloudranConfig.parallelThreads);
            end
            
            %Create Buffer
            receiverBufferCapacity = floor(sdrConfig.maxLengthOfWaveform/sdrConfig.lengthOfWaveformPerByte * cloudranConfig.dutyCycle);
            receiverAsyncBuffer = dsp.AsyncBuffer(receiverBufferCapacity);
            
            %Initialize TCPIPConnections
            tcpIpServer = TCPIPConnection.createTcpIpSocket(tcpIpConfig.tcpIpIP, tcpIpConfig.tcpIpPort, 1, receiverBufferCapacity);
            softwareFlowControlSender = TCPIPConnection.createTcpIpSocket('127.0.0.1', 1236, 0, receiverBufferCapacity);
            softwareFlowControlReceiver = TCPIPConnection.createTcpIpSocket('127.0.0.1', 1237, 1, receiverBufferCapacity);
            
            %Initialize arrays for time measurement
            softwareControlFlowSenderWaitTimes = [];
            tcpIpReceiverTimes = [];
            waveformGeneratorTimes = [];
            sdrSenderTimes = [];
            
            completeSenderTimer = tic;
            bytesSent = 0;
            unacknowledgedPackets = containers.Map('KeyType','char', 'ValueType','any');
            seqNrOffset = 0;
            waveformInd = 1;
            ackWaveforms = zeros(0, 0, 'int32');
            ackSeqNrs = zeros(0, 0, 'int16');
            while true                     
                softwareControlFlowSenderWaitTimer = tic;
                
                %Dont wait for Acknowledgements when pregenerating
                if(~cloudranConfig.pipelineProtocol)
                    %Send CloudRAN.XON signal and wait for CloudRAN.XOFF signal
                    CloudRANUtils.dispMessage("Waiting for XOFF signal...");
                    [signal, ackWaveformInds, ackSeqNrs] =  SoftwareFlowControl.waitForSignal(softwareFlowControlReceiver);
                    ackWaveforms = [ackWaveforms, ackWaveformInds];
                    if ~(signal == CloudRAN.XOFF)
                        error("Received invalid signal from flow control: " + signal);
                    end
                end
                
                %Remove acknowledged SeqNrs from map
                for ind=1:size(ackSeqNrs, 2)
                    remove(unacknowledgedPackets, ackSeqNrs(ind));
                end

                resendablePacketKeys = CloudRANUtils.getResendablePacketKeys(ackWaveforms, unacknowledgedPackets, floor(ceil(receiverBufferCapacity/sdrConfig.msduLength) * cloudranConfig.dutyCycle));
                CloudRANUtils.dispMessage("Resending " + size(resendablePacketKeys, 2) + " unacknowledged Packets...");
                
                %Check for end of transmission
                if(tcpIpServer.BytesAvailable == 0 && unacknowledgedPackets.Count == 0 && receiverAsyncBuffer.NumUnreadSamples == 0)
                    if(cloudranConfig.pipelineProtocol)
                        %Send CloudRAN.XON signal and wait for CloudRAN.XOFF signal
                        CloudRANUtils.dispMessage("Waiting for XOFF signal...");
                        [signal, ~, ~] =  SoftwareFlowControl.waitForSignal(softwareFlowControlReceiver);
                        if ~(signal == CloudRAN.XOFF)
                            error("Received invalid signal from flow control: " + signal);
                        end
                    end
                    SoftwareFlowControl.sendSignal(softwareFlowControlSender, CloudRAN.TRANSMISSIONEND);
                    
                    %Save Execution Times of Iteration
                    softwareControlFlowSenderWaitTimes = [softwareControlFlowSenderWaitTimes toc(softwareControlFlowSenderWaitTimer)];
                    tcpIpReceiverTimes = [tcpIpReceiverTimes 0];
                    waveformGeneratorTimes = [waveformGeneratorTimes 0];
                    sdrSenderTimes = [sdrSenderTimes 0];
                    break;
                end
                
                %Check if only Ack are missing
                if(tcpIpServer.BytesAvailable == 0 && isempty(resendablePacketKeys) && receiverAsyncBuffer.NumUnreadSamples == 0)
                    if(cloudranConfig.pipelineProtocol)
                        %Send CloudRAN.XON signal and wait for CloudRAN.XOFF signal
                        CloudRANUtils.dispMessage("Waiting for XOFF signal...");
                        [signal, ackWaveformInds, ackSeqNrs] =  SoftwareFlowControl.waitForSignal(softwareFlowControlReceiver);
                        ackWaveforms = [ackWaveforms, ackWaveformInds];
                        if ~(signal == CloudRAN.XOFF)
                            error("Received invalid signal from flow control: " + signal);
                        end
                    end
                    SoftwareFlowControl.sendSignal(softwareFlowControlSender, CloudRAN.NOMOREDATA);
                    
                    %Save Execution Times of Iteration
                    softwareControlFlowSenderWaitTimes = [softwareControlFlowSenderWaitTimes toc(softwareControlFlowSenderWaitTimer)];
                    tcpIpReceiverTimes = [tcpIpReceiverTimes 0];
                    waveformGeneratorTimes = [waveformGeneratorTimes 0];
                    sdrSenderTimes = [sdrSenderTimes 0];
                    continue;
                end
                
                softwareControlFlowSenderWaitTime = toc(softwareControlFlowSenderWaitTimer);
                tcpIpReceiverTimer = tic;
                
                %Get data from TCPIPConnection
                if(tcpIpServer.BytesAvailable > 0 && (receiverAsyncBuffer.Capacity - receiverAsyncBuffer.NumUnreadSamples) > 0)
                    receiverAsyncBuffer = TCPIPConnection.getDataFromTcpIpServer(tcpIpConfig.tcpIpTimeout, tcpIpServer, receiverAsyncBuffer);
                end
                
                tcpIpReceiverTime = toc(tcpIpReceiverTimer); %#ok<*AGROW>
                waveformGeneratorTimer = tic;
                
                %Extract packages from buffer
                packets = read(receiverAsyncBuffer, max(0, receiverAsyncBuffer.NumUnreadSamples - sdrConfig.msduLength*size(resendablePacketKeys, 2)));
                
                bytesSent = bytesSent + size(packets, 1);
                
                %Generate waveform
                CloudRANUtils.dispMessage("Generating Waveform " + waveformInd + "...");
                if(cloudranConfig.parallelGeneration)                    
                    [totalWaveform, unacknowledgedPackets] = ParallelWaveformGenerator.generateWaveform(sdrConfig, waveformInd, seqNrOffset, packets, unacknowledgedPackets, resendablePacketKeys);
                else
                    [totalWaveform, unacknowledgedPackets] = WaveformGenerator.generateWaveform(sdrConfig, waveformInd, seqNrOffset, packets, unacknowledgedPackets, resendablePacketKeys);
                end
                seqNrOffset = seqNrOffset + ceil(size(packets, 1)/sdrConfig.msduLength);

                waveformGeneratorTime = toc(waveformGeneratorTimer);
                
                %Wait for Signal when pregenerating the waveform
                if(cloudranConfig.pipelineProtocol)
                    softwareControlFlowSenderWaitTimer = tic;
                    
                    %Send CloudRAN.XON signal and wait for CloudRAN.XOFF signal
                    CloudRANUtils.dispMessage("Waiting for XOFF signal...");
                    [signal, ackWaveformInds, ackSeqNrs] =  SoftwareFlowControl.waitForSignal(softwareFlowControlReceiver);
                    ackWaveforms = [ackWaveforms, ackWaveformInds];
                    if ~(signal == CloudRAN.XOFF)
                        error("Received invalid signal from flow control: " + signal);
                    end
                    
                    softwareControlFlowSenderWaitTime = softwareControlFlowSenderWaitTime + toc(softwareControlFlowSenderWaitTimer);
                end
                
                sdrSenderTimer = tic;
                
                %Stop previous transmission
                if (exist('sdrTransmitter', 'var'))
                    CloudRANUtils.dispMessage("Stopping previous transmission...");
                    release(sdrTransmitter);
                end
                
                %Transmit waveform via SDR
                CloudRANUtils.dispMessage("Sending Waveform via SDR...");
                sdrTransmitter = SDRConnection.transmitWaveform(sdrConfig, totalWaveform);
                clear totalWaveform;
                
                sdrSenderTime = toc(sdrSenderTimer);
                softwareControlFlowSenderWaitTimer = tic;

                SoftwareFlowControl.sendSignal(softwareFlowControlSender, CloudRAN.XON);
                
                softwareControlFlowSenderWaitTime = softwareControlFlowSenderWaitTime + toc(softwareControlFlowSenderWaitTimer);
                
                %Save Times for current Iteration
                softwareControlFlowSenderWaitTimes = [softwareControlFlowSenderWaitTimes softwareControlFlowSenderWaitTime];
                tcpIpReceiverTimes = [tcpIpReceiverTimes tcpIpReceiverTime];
                waveformGeneratorTimes = [waveformGeneratorTimes waveformGeneratorTime];
                sdrSenderTimes = [sdrSenderTimes sdrSenderTime];
                
                waveformInd = waveformInd+1;
            end
            
            %Stop previous transmission
            if (exist('sdrTransmitter', 'var'))
                CloudRANUtils.dispMessage("Stopping previous transmission...");
                release(sdrTransmitter);
            end
            
            %Close TCPIPConnections
            fclose(tcpIpServer);
            fclose(softwareFlowControlSender);
            fclose(softwareFlowControlReceiver);
            
            %Save execution times
            completeSenderTime = toc(completeSenderTimer);
            CloudRANUtils.saveSenderExecutionTimes(cloudranConfig.parallelGeneration, completeSenderTime, bytesSent, softwareControlFlowSenderWaitTimes, tcpIpReceiverTimes, waveformGeneratorTimes, sdrSenderTimes);
        end
        
        % This method starts the CloudRAN Receiver, which receives data from a SDR and
        % sends it to a Client via TcpIp.
        function startReceiver()
            
            clear;
            
            %Configuration file path
            configPath = "./config/receiverconfig.conf";
            CloudRANUtils.showConfiguration(configPath)
            
            %Read configuration values
            cloudranConfig = CloudRANConfiguration.readConfigValues(configPath);
            sdrConfig = SDRConfiguration.readConfigValues(configPath);
            tcpIpConfig = TCPIPConfiguration.readConfigValues(configPath);
            
            %Create/Shutdown parpool if needed
            if ((~cloudranConfig.parallelDecoding && ~isempty(gcp('nocreate'))) || ...
                    (cloudranConfig.parallelDecoding && ~isempty(gcp('nocreate')) && gcp('nocreate').NumWorkers ~= cloudranConfig.parallelThreads))
                delete(gcp('nocreate'))
            end
            if cloudranConfig.parallelDecoding && isempty(gcp('nocreate'))
                parpool(cloudranConfig.parallelThreads);
            end
            
            %Initialize TCPIPConnections
            tcpIpCapacity = floor(sdrConfig.maxLengthOfWaveform/sdrConfig.lengthOfWaveformPerByte);
            tcpIpClient = TCPIPConnection.createTcpIpSocket(tcpIpConfig.tcpIpIP, tcpIpConfig.tcpIpPort, 0, tcpIpCapacity);
            softwareFlowControlReceiver = TCPIPConnection.createTcpIpSocket('127.0.0.1', 1236, 1, tcpIpCapacity);
            softwareFlowControlSender = TCPIPConnection.createTcpIpSocket('127.0.0.1', 1237, 0, tcpIpCapacity);
            
            %Initialize arrays for time measurement
            softwareControlFlowReceiverWaitTimes = [];
            sdrReceiverTimes = [];
            waveformDecoderTimes = [];
            tcpIpSenderTimes = [];
            
            completeReceiverTimer = tic;
            expectedStartSeqNr = 1;
            previouslyRemaingingPackets = containers.Map('KeyType','double', 'ValueType','any');
            
            %Send first Start signal
            softwareControlFlowReceiverWaitTimer = tic;
            
            SoftwareFlowControl.sendSignal(softwareFlowControlSender, CloudRAN.XOFF); 
            
            softwareControlFlowReceiverWaitTime = toc(softwareControlFlowReceiverWaitTimer);
            waveformInd = 1;
            bytesReceived = 0;
            threads = [];
            while true
                
                softwareControlFlowReceiverWaitTimer = tic;
                
                %Wait for CloudRAN.XON signal
                CloudRANUtils.dispMessage("Waiting for XON signal...");
                signal = SoftwareFlowControl.waitForSignal(softwareFlowControlReceiver);
                if(signal == CloudRAN.TRANSMISSIONEND)
                    break;
                end
                if signal ~= CloudRAN.XON && signal ~= CloudRAN.NOMOREDATA
                    error("Received invalid signal from flow control: " + signal);
                end
                
                softwareControlFlowReceiverWaitTime = softwareControlFlowReceiverWaitTime + toc(softwareControlFlowReceiverWaitTimer);
                
                %If Sender is waiting for remaining Acknowledgements 
                %get Data from remaining Workerthreads and send Acknowledgements
                if(signal == CloudRAN.NOMOREDATA)
                    tcpIpSenderTime = 0;
                    waveformDecoderTime = 0;
                    
                    allReceivedSeqNrs = zeros(0, 0, 'int16');
                    waveformInds = zeros(1, size(threads, 2), 'int16');
                    for ind=1:size(threads, 2)
                        waveformDecoderTimer = tic;
                        
                        [receivedPackets, receivedSeqNrs] = fetchOutputs(threads(ind));
                        
                        CloudRANUtils.dispMessage("Decoded Waveform: " + waveformInd);
                        CloudRANUtils.dispMessage("Decoded SeqNrs: " + num2str(receivedSeqNrs));
                        
                        if(~cloudranConfig.selectiveAck)
                            allReceivedSeqNrs = [allReceivedSeqNrs -1 CloudRANUtils.getFirstSequence(expectedStartSeqNr, receivedSeqNrs)];
                        else
                            allReceivedSeqNrs = [allReceivedSeqNrs -1 receivedSeqNrs];
                        end
                        
                        waveformInds(ind) = waveformInd; 
                        waveformInd = waveformInd+1;
                        
                        if(previouslyRemaingingPackets.Count ~= 0)
                            [receivedPackets, receivedSeqNrs] = CloudRANUtils.mergeReceivedPackets(receivedPackets, receivedSeqNrs, previouslyRemaingingPackets);
                        end
                        
                        waveformDecoderTime = waveformDecoderTime + toc(waveformDecoderTimer);
                        tcpIpSenderTimer = tic;
                        
                        CloudRANUtils.dispMessage("Sending Data to Client...");
                        [expectedStartSeqNr, previouslyRemaingingPackets, bytesProcessed] = TCPIPConnection.extractAndSendData(cloudranConfig, sdrConfig, tcpIpClient, expectedStartSeqNr, receivedSeqNrs, receivedPackets, previouslyRemaingingPackets);
                        bytesReceived = bytesReceived + bytesProcessed;
                        
                        tcpIpSenderTime = tcpIpSenderTime + toc(tcpIpSenderTimer);
                    end
                    
                    %Remove first -1 from allReceivedSeqNrs and clear
                    %threads
                    if(~isempty(allReceivedSeqNrs))
                        allReceivedSeqNrs(1) = [];
                    end
                    threads = [];
                    
                    softwareControlFlowReceiverWaitTimer = tic;

                    %Send Acknowlege
                    SoftwareFlowControl.sendSignal(softwareFlowControlSender, CloudRAN.XOFF, waveformInds, allReceivedSeqNrs); 
                    CloudRANUtils.dispMessage("Acknowledging " + (size(allReceivedSeqNrs, 2)-sum(allReceivedSeqNrs == -1)) + " Packets...");
                    
                    softwareControlFlowReceiverWaitTime = softwareControlFlowReceiverWaitTime + toc(softwareControlFlowReceiverWaitTimer);
                    
                    %Save Execution Times of Iteration
                    softwareControlFlowReceiverWaitTimes = [softwareControlFlowReceiverWaitTimes softwareControlFlowReceiverWaitTime];
                    sdrReceiverTimes = [sdrReceiverTimes 0];
                    waveformDecoderTimes = [waveformDecoderTimes waveformDecoderTime];
                    tcpIpSenderTimes = [tcpIpSenderTimes tcpIpSenderTime];
                    softwareControlFlowReceiverWaitTime = 0;
                    continue;
                end
                
                sdrCommunicatorTimer = tic;
                
                %Receive waveform via SDR
                CloudRANUtils.dispMessage("Listening to Waveform...");
                receivedWaveform = SDRConnection.receiveWaveform(sdrConfig);
                
                CloudRANUtils.dispMessage("Received Waveform from SDR...");
                
                sdrReceiverTime = toc(sdrCommunicatorTimer);
                waveformDecoderTimer = tic;
                
                %Decode waveform with selected Decoding Mode
                CloudRANUtils.dispMessage("Decoding Waveform...");
                if(~cloudranConfig.parallelDecoding || strcmp(cloudranConfig.parallelDecodingMode, "Frame"))
                    if(cloudranConfig.parallelDecoding)
                        [receivedPackets, receivedSeqNrs] = ParallelWaveformGenerator.decodeWaveform(sdrConfig, receivedWaveform);
                    else
                        [receivedPackets, receivedSeqNrs] = WaveformGenerator.decodeWaveform(sdrConfig, receivedWaveform);
                    end
                    clear receivedWaveform;
                    
                    CloudRANUtils.dispMessage("Decoded Waveform: " + waveformInd);
                    CloudRANUtils.dispMessage("Decoded SeqNrs: " + num2str(receivedSeqNrs));
                    
                    if(previouslyRemaingingPackets.Count ~= 0)
                        [receivedPackets, mergedSeqNrs] = CloudRANUtils.mergeReceivedPackets(receivedPackets, receivedSeqNrs, previouslyRemaingingPackets);
                    else
                        mergedSeqNrs = receivedSeqNrs;
                    end
                    
                    waveformDecoderTime = toc(waveformDecoderTimer);
                    softwareControlFlowReceiverWaitTimer = tic;
                    
                    %Send Acknowlege
                    if(~cloudranConfig.selectiveAck)
                        ackSeqNrs = CloudRANUtils.getFirstSequence(expectedStartSeqNr, receivedSeqNrs);
                        SoftwareFlowControl.sendSignal(softwareFlowControlSender, CloudRAN.XOFF, waveformInd, ackSeqNrs);
                        CloudRANUtils.dispMessage("Acknowledging " + size(ackSeqNrs, 2) + " Packets...");
                    else
                        SoftwareFlowControl.sendSignal(softwareFlowControlSender, CloudRAN.XOFF, waveformInd, receivedSeqNrs); 
                        CloudRANUtils.dispMessage("Acknowledging " + size(receivedSeqNrs,2) + " Packets...");
                    end
                    
                    softwareControlFlowReceiverWaitTime = softwareControlFlowReceiverWaitTime + toc(softwareControlFlowReceiverWaitTimer);
                    tcpIpSenderTimer = tic;

                    CloudRANUtils.dispMessage("Sending Data to Client...");
                    [expectedStartSeqNr, previouslyRemaingingPackets, bytesProcessed] = TCPIPConnection.extractAndSendData(cloudranConfig, sdrConfig, tcpIpClient, expectedStartSeqNr, mergedSeqNrs, receivedPackets, previouslyRemaingingPackets);
                    
                    bytesReceived = bytesReceived + bytesProcessed;
                    tcpIpSenderTime = toc(tcpIpSenderTimer);
                    waveformInd = waveformInd+1;
                else
                    %Start Thread to decode Waveform
                    t = parfeval(@WaveformGenerator.decodeWaveform, 2, sdrConfig, receivedWaveform);
                    threads = [threads t];
                    
                    waveformDecoderTime = toc(waveformDecoderTimer);
                    tcpIpSenderTime = 0;
                    
                    %Check if any of the threads decoding a waveform are
                    %finished
                    allReceivedSeqNrs = [];
                    waveformInds = [];
                    finishedThreads = [];
                    for ind=1:size(threads, 2)
                        waveformDecoderTimer = tic;
                        if strcmp(threads(ind).State, 'failed')
                            error("Waveform Decoding Thread failed: " + threads(ind).Error);
                        end
                        if ~strcmp(threads(ind).State, 'finished')
                            continue;
                        end
                        [receivedPackets, receivedSeqNrs] = fetchOutputs(threads(ind));
                        finishedThreads = [finishedThreads ind];
                        
                        CloudRANUtils.dispMessage("Decoded Waveform: " + waveformInd);
                        CloudRANUtils.dispMessage("Decoded SeqNrs: " + num2str(receivedSeqNrs));
                        
                        if(~cloudranConfig.selectiveAck)
                            allReceivedSeqNrs = [allReceivedSeqNrs -1 CloudRANUtils.getFirstSequence(expectedStartSeqNr, receivedSeqNrs)];
                        else
                            allReceivedSeqNrs = [allReceivedSeqNrs -1 receivedSeqNrs];
                        end
                        
                        waveformInds = [waveformInds waveformInd];
                        waveformInd = waveformInd+1;
                        
                        if(previouslyRemaingingPackets.Count ~= 0)
                            [receivedPackets, receivedSeqNrs] = CloudRANUtils.mergeReceivedPackets(receivedPackets, receivedSeqNrs, previouslyRemaingingPackets);
                        end
                        
                        waveformDecoderTime = waveformDecoderTime + toc(waveformDecoderTimer);
                        tcpIpSenderTimer = tic;
                        
                        CloudRANUtils.dispMessage("Sending Data to Client...");
                        [expectedStartSeqNr, previouslyRemaingingPackets, bytesProcessed] = TCPIPConnection.extractAndSendData(cloudranConfig, sdrConfig, tcpIpClient, expectedStartSeqNr, receivedSeqNrs, receivedPackets, previouslyRemaingingPackets);
                        bytesReceived = bytesReceived + bytesProcessed;
                        
                        tcpIpSenderTime = tcpIpSenderTime + toc(tcpIpSenderTimer);
                    end
                    threads(finishedThreads) = [];
                    if(~isempty(allReceivedSeqNrs))
                        allReceivedSeqNrs(1) = [];
                    end
                    
                    softwareControlFlowReceiverWaitTimer = tic;

                    %Send Acknowlege
                    SoftwareFlowControl.sendSignal(softwareFlowControlSender, CloudRAN.XOFF, waveformInds, allReceivedSeqNrs);
                    CloudRANUtils.dispMessage("Acknowledging " + (size(allReceivedSeqNrs, 2)-sum(allReceivedSeqNrs == -1)) + " Packets...");
                    
                    softwareControlFlowReceiverWaitTime = softwareControlFlowReceiverWaitTime + toc(softwareControlFlowReceiverWaitTimer);
                end
                
                %Save Execution Times of Iteration
                softwareControlFlowReceiverWaitTimes = [softwareControlFlowReceiverWaitTimes softwareControlFlowReceiverWaitTime];
                sdrReceiverTimes = [sdrReceiverTimes sdrReceiverTime];
                waveformDecoderTimes = [waveformDecoderTimes waveformDecoderTime];
                tcpIpSenderTimes = [tcpIpSenderTimes tcpIpSenderTime];
                softwareControlFlowReceiverWaitTime = 0;
                clear receivedPackets;
            end           
            
            %Close TCPIPConnections
            fclose(tcpIpClient);
            fclose(softwareFlowControlSender);
            fclose(softwareFlowControlReceiver);
            
            %Save execution times
            completeReceiverTime = toc(completeReceiverTimer);
            CloudRANUtils.saveReceiverExecutionTimes(cloudranConfig.parallelDecoding, completeReceiverTime, bytesReceived, softwareControlFlowReceiverWaitTimes, tcpIpSenderTimes, waveformDecoderTimes, sdrReceiverTimes);
        end
    end
end