#!/bin/bash

if [ -f "./ReceiverPlotData.mat" ]
then
	rm -f "./ReceiverPlotData.mat"
fi

if [ -f "./SenderPlotData.mat" ]
then
	rm -f "./SenderPlotData.mat"
fi

matlab -nosplash -nodesktop -r "CloudRAN.startSender()" > matlab_sender.log &
matlabSenderPID=$!
	
matlab -nosplash -nodesktop -r "CloudRAN.startReceiver()" > matlab_receiver.log &
matlabReceiverPID=$!
	
nc -l 127.0.0.1 1235 > ./received.txt &
	
sleep 30
	
nc 127.0.0.1 1234 < $1
	
kill $matlabSenderPID
kill $matlabReceiverPID
