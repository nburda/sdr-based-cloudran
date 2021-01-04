@echo off

if exist "./ReceiverPlotData.mat" (
	del "./ReceiverPlotData.mat"
)

if exist "./SenderPlotData.mat" (
	del "./SenderPlotData.mat"
)

matlab -nosplash -nodesktop -r "CloudRAN.startSender()" > matlab_sender.log	
matlab -nosplash -nodesktop -r "CloudRAN.startReceiver()" > matlab_receiver.log
	
start /b ncat -l 127.0.0.1 1235 > ./received.txt
	
ping 192.0.2.2 -n 1 -w 30000 > nul
	
ncat 127.0.0.1 1234 < %1
	
taskkill /f /im "matlab.exe"

exit