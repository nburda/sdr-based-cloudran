% This class contains utility functions for the CloudRAN.
classdef CloudRANUtils
    methods (Static)
        % This method shows the given message with a timestamp.
        function dispMessage(msg)
            disp(datestr(now,'HH:MM:SS.FFF') + " - " + msg)
        end
        
        % This method reads the configuration values from given the
        % configuration file.
        function value = getConfigValue(configPath, valueName)
            value = "";
            fid = fopen(configPath);
            while ~feof(fid)
                line = fgetl(fid); 
                if contains(line, valueName)
                    value = extractAfter(line, "=");
                    fclose(fid);
                    return;
                end                
            end
            fclose(fid);
        end
        
        % This method shows all used configuration values.
        function showConfiguration(configPath)
            width = 100;
            borderwidth = 10;
            fid = fopen(configPath);
            fprintf(repelem('-', width));
            if(contains(fileread(configPath), "Generation"))
                fprintf("\n" + pad("Starting C-RAN Sender...", width, 'both'));
            else
                fprintf("\n" + pad("Starting C-RAN Receiver...", width, 'both'));
            end

            fprintf("\n\nUsed Configuration:\n");
            
            while ~feof(fid)
                line = fgetl(fid); 
                arg = extractBefore(line, "=");
                value = extractAfter(line, "=");
                fprintf("\n" + repelem(' ', borderwidth) + arg + pad(" - ", width/2-strlength(arg)-borderwidth, 'left') + pad(value, width/2-borderwidth, 'left'));               
            end
            fclose(fid);
            fprintf("\n" + repelem('-', width) + "\n\n\n");
        end
        
        % This method shows the execution times of the transmission.
        function showExecutionTimes(isSender, completeTime, bytesProcessed, softwareControlFlowWaitTimes, tcpIpTimes, waveformProcessingTimes , sdrTimes)
            width = 100;
            borderwidth = 10;
            fprintf("\n\n" + repelem('-', width))
            if(isSender)
                fprintf("\n" + pad("Shutting C-RAN Sender down...", width, 'both'))
            else
                fprintf("\n" + pad("Shutting C-RAN Receiver down...", width, 'both'))
            end

            fprintf("\n\nExecution Times:\n")
            
            fprintf("\n" + repelem(' ', borderwidth) + "Overall Execution" + pad(" - ", width/2-strlength("Overall Execution")-borderwidth, 'left') + pad(completeTime + " s", width/2-borderwidth, 'left'));
            fprintf("\n" + repelem(' ', borderwidth) + "Bytes processed" + pad(" - ", width/2-strlength("Bytes processed")-borderwidth, 'left') + pad(bytesProcessed + " B", width/2-borderwidth, 'left'));
            fprintf("\n" + repelem(' ', borderwidth) + "Data Rate" + pad(" - ", width/2-strlength("Data Rate")-borderwidth, 'left') + pad(round(((bytesProcessed/completeTime)/1000)*8, 1) + " kbit/s", width/2-borderwidth, 'left'));
            
            if(isSender)
                fprintf("\n" + repelem(' ', borderwidth) + "Wait for CloudRAN Receiver" + pad(" - ", width/2-strlength("Wait for CloudRAN Receiver")-borderwidth, 'left') + pad(sum(softwareControlFlowWaitTimes) + " s", width/2-borderwidth, 'left'));
                fprintf("\n" + repelem(' ', borderwidth) + "Receive Data from Server" + pad(" - ", width/2-strlength("Receive Data from Server")-borderwidth, 'left') + pad(sum(tcpIpTimes) + " s", width/2-borderwidth, 'left'));
                fprintf("\n" + repelem(' ', borderwidth) + "Generate Waveform" + pad(" - ", width/2-strlength("Generate Waveform")-borderwidth, 'left') + pad(sum(waveformProcessingTimes) + " s", width/2-borderwidth, 'left'));
                fprintf("\n" + repelem(' ', borderwidth) + "Send Waveform via SDR" + pad(" - ", width/2-strlength("Send Waveform via SDR")-borderwidth, 'left') + pad(sum(sdrTimes) + " s", width/2-borderwidth, 'left'));
            else
                fprintf("\n" + repelem(' ', borderwidth) + "Wait for CloudRAN Transmitter" + pad(" - ", width/2-strlength("Wait for CloudRAN Transmitter")-borderwidth, 'left') + pad(sum(softwareControlFlowWaitTimes) + " s", width/2-borderwidth, 'left'));
                fprintf("\n" + repelem(' ', borderwidth) + "Send Data to Client" + pad(" - ", width/2-strlength("Send Data to Client")-borderwidth, 'left') + pad(sum(tcpIpTimes) + " s", width/2-borderwidth, 'left'));
                fprintf("\n" + repelem(' ', borderwidth) + "Decode Waveform" + pad(" - ", width/2-strlength("Decode Waveform")-borderwidth, 'left') + pad(sum(waveformProcessingTimes) + " s", width/2-borderwidth, 'left'));
                fprintf("\n" + repelem(' ', borderwidth) + "Receive Waveform via SDR" + pad(" - ", width/2-strlength("Receive Waveform via SDR")-borderwidth, 'left') + pad(sum(sdrTimes) + " s", width/2-borderwidth, 'left')); 
            end
            fprintf("\n" + repelem('-', width) +"\n")
        end
        
        % This method returns the first sequence in an array based on a given starting
        % position (4095 being handled as the predecessor of 1).
        function firstSequence = getFirstSequence(seqStart, seqNrs)
            seq = sort(seqNrs);
            s = find(seq==seqStart);
            if (isempty(s))
                firstSequence = zeros(0, 0,'int16');
                return;
            end
            if(size(seq, 2) == 1)
                firstSequence = seq;
                return;
            end
            if(s+1 > size(seqNrs, 2))
                firstSequence = zeros(1, 1,'int16');
                firstSequence(1) = seq(s);
                return;
            end
            firstSequence = zeros(1, size(seqNrs, 2),'int16');
            firstSequence(1) = seq(s);
            ind = 2;
            while(seq(s)+1 == seq(s+1))
                firstSequence(ind) = seq(s+1);
                s = s+1;
                ind = ind+1;
                if(seq(s) == 4095 && seq(1) == 1)
                    firstSequence(ind) = 1;
                    s = 1;
                    ind = ind+1;
                end
                if(s+1 > size(seqNrs, 2))
                    break;
                end
            end
            firstSequence = nonzeros(firstSequence)';
        end
        
        % This method merges the Buffer containing newly received Packets with the
        % already received Packets from earlier waveforms.
        function [mergedPackets, mergedSeqNrs] = mergeReceivedPackets(packets, seqNrs, alreadyReceivedPackets)
            mapKeys = CloudRANUtils.flattenMapKeys(keys(alreadyReceivedPackets));
            mergedSeqNrs = sort([mapKeys, seqNrs]);
            mergedPackets = cell(size(seqNrs, 2)+size(mapKeys,2), 1);
            if(~isempty(seqNrs))
                for ind = 1:size(seqNrs, 2)
                    mergedPackets{seqNrs(ind)} = packets{seqNrs(ind)};
                end
            end
            for ind = 1:size(mapKeys,2)
                mergedPackets{mapKeys(ind)} = alreadyReceivedPackets(mapKeys(ind));
            end
        end
        
        % This method gets the packet keys of all resendable packets from
        % the given packetMap, that should be sent in the next waveform.
        function packetKeys = getResendablePacketKeys(waveformInds, packetMap, packetsPerWaveform)
            packetKeys = [];
            mapKeys = keys(packetMap);
            for ind=1:min(size(waveformInds, 2), packetsPerWaveform)
                packetKeys = [packetKeys mapKeys(startsWith(mapKeys, "W"+waveformInds(ind)+"I"))];
            end
            if(size(packetKeys, 2) > packetsPerWaveform)
                packetKeys = packetKeys(1:packetsPerWaveform);
            end
        end
        
        % This method flattens the given map keys into a single array.
        function flattenedKeys = flattenMapKeys(keys)
            flattenedKeys = zeros(size(keys), 'int16');
            for ind=1:size(keys, 2)
                key = keys(ind);
                flattenedKeys(ind) = key{1};
            end
        end
        
        % This method removes trailing zeros from a given array.
        function arr = removeTrailingZeros(arr)
            arr = arr(1:find(arr,1,'last'));
        end
        
        % This method shows and saves all revelant execution data for the sender.
        function saveSenderExecutionTimes(parallelGeneration, completeSenderTime, bytesSent, softwareControlFlowSenderWaitTimes, tcpIpReceiverTimes, waveformGeneratorTimes, sdrSenderTimes)
            CloudRANUtils.showExecutionTimes(true, completeSenderTime, bytesSent, softwareControlFlowSenderWaitTimes, tcpIpReceiverTimes, waveformGeneratorTimes , sdrSenderTimes);
            
            if(parallelGeneration)
                prefix = "Parallel";
            else
                prefix = "Nonparallel";
            end
            senderPlotTitle =  prefix + " CloudRAN Sender Execution (" + round(completeSenderTime, 1) + "s)";
            
            senderPlotValues{1} = softwareControlFlowSenderWaitTimes;
            senderPlotValues{2} = tcpIpReceiverTimes;
            senderPlotValues{3} = waveformGeneratorTimes;
            senderPlotValues{4} = sdrSenderTimes;
            
            if (parallelGeneration)
                waveformGeneratorLabel = 'Generate Waveform (Parallel)';
            else
                waveformGeneratorLabel = 'Generate Waveform';
            end
            senderPlotLabels{1} = 'Wait for CloudRAN Receiver';
            senderPlotLabels{2} = 'Receive Data from Server';
            senderPlotLabels{3} = waveformGeneratorLabel;
            senderPlotLabels{4} = 'Send Waveform via SDR';
            
            %Save plot data 
            save('SenderPlotData.mat','senderPlotTitle','senderPlotValues','senderPlotLabels', 'completeSenderTime', 'bytesSent');
        end
        
        % This method shows and saves all revelant execution data for the receiver.
        function saveReceiverExecutionTimes(parallelDecoding, completeReceiverTime, bytesReceived, softwareControlFlowReceiverWaitTimes, tcpIpSenderTimes, waveformDecoderTimes, sdrReceiverTimes)
            CloudRANUtils.showExecutionTimes(false, completeReceiverTime, bytesReceived, softwareControlFlowReceiverWaitTimes, tcpIpSenderTimes, waveformDecoderTimes , sdrReceiverTimes);
            
            if(parallelDecoding)
                prefix = "Parallel";
            else
                prefix = "Nonparallel";
            end
            receiverPlotTitle =  prefix + " CloudRAN Receiver Execution (" + round(completeReceiverTime, 1) + "s)";
            
            receiverPlotValues{1} = softwareControlFlowReceiverWaitTimes;
            receiverPlotValues{2} = tcpIpSenderTimes;
            receiverPlotValues{3} = waveformDecoderTimes;
            receiverPlotValues{4} = sdrReceiverTimes;
            
            if (parallelDecoding)
                waveformDecoderLabel = 'Decode Waveform (Parallel)';
            else
                waveformDecoderLabel = 'Decode Waveform';
            end
            
            receiverPlotLabels{1} = 'Wait for CloudRAN Transmitter';
            receiverPlotLabels{2} = 'Send Data to Client';
            receiverPlotLabels{3} = waveformDecoderLabel;
            receiverPlotLabels{4} = 'Receive Waveform via SDR';
            
            %Save plot data 
            save('ReceiverPlotData.mat','receiverPlotTitle','receiverPlotValues','receiverPlotLabels', 'completeReceiverTime', 'bytesReceived');
        end
        
        % This method creates a Box plot from the given values and labels.
        function createBoxPlot(plotTitle, plotValues, givenPlotLabels, executionTime, bytesProcessed)
            
            assert(size(plotValues, 2) == size(givenPlotLabels, 2));
            
            givenPlotLabels = pad(givenPlotLabels);
            
            plotTimes = [];
            plotLabels = [];
            for ind = 1:size(plotValues, 2)
                plotTimes = [plotTimes, nonzeros(plotValues{ind})'];  %#ok<*AGROW>
                plotLabels = vertcat(plotLabels, repmat(givenPlotLabels{ind}, size(nonzeros(plotValues{ind}), 1), 1));
            end
            plotTimes = plotTimes';
            
            figure('Name','Boxplot');
            boxplot(plotTimes, plotLabels);
            title(plotTitle);
            ylabel('Time in Seconds');
            annotation('textbox',[0.2 0.5 0.3 0.3],'String',{"Execution Time: " + round(executionTime, 1) + " s", "Bytes processed: " + bytesProcessed + " B", "Datarate: " + round(((bytesProcessed/executionTime)/1000)*8, 1) + " kbit/s"},'FitBoxToText','on');
        
            if ~exist("./figures", 'dir')
                mkdir("./figures")
            end
            
            savefig("./figures/" + plotTitle +  " Box Plot.fig");
        end
        
        % This method creates a Pie chart from the given values and labels.
        function createPieChart(plotTitle, plotValues, plotLabels, executionTime, bytesProcessed)
            
            assert(size(plotValues, 2) == size(plotLabels, 2));
            
            plotTimes = [];
            for ind = 1:size(plotValues, 2)
                plotTimes = [plotTimes sum(plotValues{ind})];
            end
            
            figure('Name','Pieplot');
            piePlot = pie(plotTimes);
            title(plotTitle);
            annotation('textbox',[0.2 0.5 0.3 0.3],'String',{"Execution Time: " + round(executionTime, 1) + " s", "Bytes processed: " + bytesProcessed + " B", "Datarate: " + round(((bytesProcessed/executionTime)/1000)*8, 1) + " kbit/s"},'FitBoxToText','on');
            plotText = findobj(piePlot,'Type','text');
            percentValues = get(plotText,'String'); 

            for ind = 1:size(plotLabels, 2)
                plotText(ind).String = append(strcat(plotLabels{ind},' (', string(round(plotTimes(ind), 1)),' s): ', percentValues(ind)));
            end
            
            if ~exist("./figures", 'dir')
                mkdir("./figures")
            end
            
            savefig("./figures/" + plotTitle +  " Pie Chart.fig");
        end
        
        % This method creates a Stacked Area chart from the given values and labels.
        function createStackedAreaChart(plotTitle, plotValues, plotLabels, executionTime, bytesProcessed)
            
            assert(size(plotValues, 2) == size(plotLabels, 2));
            
            sizes = [];
            for ind = 1:size(plotValues, 2)
                sizes = [sizes size(plotValues{ind}, 2)];
            end
            % pad plotValues
            for ind = 1:size(plotValues, 2)
                plotValues{ind} = [plotValues{ind} zeros(1,max(sizes) - size(plotValues{ind},2))];
            end
            
            plotTimes = [];
            for ind = 1:max(sizes)
                elementsForStep = [];
                for x = 1:size(plotValues, 2)
                    elementsForStep = [elementsForStep plotValues{x}(ind)];
                end
                plotTimes = [plotTimes; elementsForStep]; 
            end
            
            figure('Name','Stacked Area plot');
            area(plotTimes);
            title(plotTitle);
            ylabel('Time in Seconds');
            xlabel('Number of Iteration');
            annotation('textbox',[0.2 0.5 0.3 0.3],'String',{"Execution Time: " + round(executionTime, 1) + " s", "Bytes processed: " + bytesProcessed + " B", "Datarate: " + round(((bytesProcessed/executionTime)/1000)*8, 1) + " kbit/s"},'FitBoxToText','on');
            legend(plotLabels);
            
            if ~exist("./figures", 'dir')
                mkdir("./figures")
            end
            
            savefig("./figures/" + plotTitle +  " Stacked Area.fig");
        end
        
        % This method creates a Bar chart from the given values and labels.
        function createBarChart(plotTitle, plotValues, plotLabels, executionTime, bytesProcessed)
            
            assert(size(plotValues, 2) == size(plotLabels, 2));
            
            plotTimes = [];
            for ind = 1:size(plotValues, 2)
                plotTimes = [plotTimes sum(plotValues{ind})];
            end
            
            orderedPlotLabels = categorical(plotLabels);
            orderedPlotLabels = reordercats(orderedPlotLabels, plotLabels);
            
            figure('Name','Pieplot');
            bar(orderedPlotLabels, plotTimes);
            title(plotTitle);
            ylabel('Time in Seconds');
            annotation('textbox',[0.2 0.5 0.3 0.3],'String',{"Execution Time: " + round(executionTime, 1) + " s", "Bytes processed: " + bytesProcessed + " B", "Datarate: " + round(((bytesProcessed/executionTime)/1000)*8, 1) + " kbit/s"},'FitBoxToText','on');
            
            if ~exist("./figures", 'dir')
                mkdir("./figures")
            end
            
            savefig("./figures/" + plotTitle +  " Bar Chart.fig");
        end
        
        % This method merges the plotdata from multiple given files and displays the
        % result as a Bar chart.
        function mergePlotData(arrOfInputFiles)
            senderData = {};
            receiverData = {};
            executionTimes = {};
            for i=1:size(arrOfInputFiles, 2)
                load(arrOfInputFiles{i}, 'senderPlotValues', 'receiverPlotValues', 'senderPlotLabels', 'receiverPlotLabels', 'completeSenderTime', 'completeReceiverTime');
                if(exist('senderPlotValues', 'var'))
                    for j=1:size(senderPlotValues, 2)
                        if(size(senderData, 2) < j)
                            senderData{j} = sum(senderPlotValues{j});
                        else
                            senderData{j} = [senderData{j}; sum(senderPlotValues{j})];
                        end
                    end
                    senderLabels = senderPlotLabels;
                    executionTimes{end+1} = "Execution Time: " + round(completeSenderTime, 1) + " s";
                end
                if(exist('receiverPlotValues', 'var'))
                    for j=1:size(receiverPlotValues, 2)
                        if(size(receiverData, 2) < j)
                            receiverData{j} = sum(receiverPlotValues{j});
                        else
                            receiverData{j} = [receiverData{j}; sum(receiverPlotValues{j})];
                        end
                    end
                    receiverLabels = receiverPlotLabels;
                    executionTimes{end+1} = "Execution Time: " + round(completeReceiverTime, 1) + " s";
                end
                clear('senderPlotValues', 'receiverPlotValues', 'senderPlotLabels', 'receiverPlotLabels');
            end
            if(~isempty(senderData))
                orderedPlotLabels = categorical(senderLabels);
                orderedPlotLabels = reordercats(orderedPlotLabels, senderLabels);

                figure('Name','Pieplot');
                bar(orderedPlotLabels, cell2mat(senderData));
                title("Sender Times");
                ylabel('Time in Seconds');
                annotation('textbox',[0.2 0.5 0.3 0.3],'String',executionTimes, 'FitBoxToText','on');
                
                if ~exist("./figures", 'dir')
                    mkdir("./figures")
                end
                
                savefig("./figures/Sender Times Bar Chart.fig");
            end
            if(~isempty(receiverData))
                orderedPlotLabels = categorical(receiverLabels);
                orderedPlotLabels = reordercats(orderedPlotLabels, receiverLabels);

                figure('Name','Pieplot');
                bar(orderedPlotLabels, cell2mat(receiverData));
                title("Receiver Times");
                ylabel('Time in Seconds');
                annotation('textbox',[0.2 0.5 0.3 0.3],'String',executionTimes, 'FitBoxToText','on');
                
                if ~exist("./figures", 'dir')
                    mkdir("./figures")
                end
                
                savefig("./figures/Receiver Times Bar Chart.fig");
            end
        end
    end
end