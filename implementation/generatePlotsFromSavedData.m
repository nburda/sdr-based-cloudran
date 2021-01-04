clear;

load SenderPlotData.mat
load ReceiverPlotData.mat

CloudRANUtils.createBoxPlot(senderPlotTitle, senderPlotValues, senderPlotLabels, completeSenderTime, bytesSent);
CloudRANUtils.createPieChart(senderPlotTitle, senderPlotValues, senderPlotLabels, completeSenderTime, bytesSent);
CloudRANUtils.createStackedAreaChart(senderPlotTitle, senderPlotValues, senderPlotLabels, completeSenderTime, bytesSent);
CloudRANUtils.createBarChart(senderPlotTitle, senderPlotValues, senderPlotLabels, completeSenderTime, bytesSent);

CloudRANUtils.createBoxPlot(receiverPlotTitle, receiverPlotValues, receiverPlotLabels, completeReceiverTime, bytesReceived);
CloudRANUtils.createPieChart(receiverPlotTitle, receiverPlotValues, receiverPlotLabels, completeReceiverTime, bytesReceived);
CloudRANUtils.createStackedAreaChart(receiverPlotTitle, receiverPlotValues, receiverPlotLabels, completeReceiverTime, bytesReceived);
CloudRANUtils.createBarChart(receiverPlotTitle, receiverPlotValues, receiverPlotLabels, completeReceiverTime, bytesReceived);

for ind = 1:size(senderPlotValues, 2)
    plotValues{ind} = senderPlotValues{ind}; %#ok<*SAGROW>
end
for ind = 1:size(receiverPlotValues, 2)
    plotValues{size(senderPlotValues, 2) + ind} = receiverPlotValues{ind};
end

for ind = 1:size(senderPlotLabels, 2)
    plotLabels{ind} = senderPlotLabels{ind};
end
for ind = 1:size(receiverPlotLabels, 2)
    plotLabels{size(senderPlotLabels, 2) + ind} = receiverPlotLabels{ind};
end

CloudRANUtils.createBoxPlot("", plotValues, plotLabels, completeReceiverTime, bytesReceived);
CloudRANUtils.createPieChart("", plotValues, plotLabels, completeReceiverTime, bytesReceived);
CloudRANUtils.createStackedAreaChart("", plotValues, plotLabels, completeReceiverTime, bytesReceived);
CloudRANUtils.createBarChart("", plotValues, plotLabels, completeReceiverTime, bytesReceived);