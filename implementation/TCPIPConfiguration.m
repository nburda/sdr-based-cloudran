% This class stores the configuration values which are related to the
% TCPIP functionality.
classdef TCPIPConfiguration
    properties
        tcpIpIP
        tcpIpPort
        tcpIpTimeout
        senderSoftwareFlowControlIP
        senderSoftwareFlowControlPort
        receiverSoftwareFlowControlIP
        receiverSoftwareFlowControlPort
    end
    methods (Static)
        % This method reads all TCPIP related configuration values from a given
        % config file.
        function config = readConfigValues(configPath)
            config = TCPIPConfiguration;
            config.tcpIpIP = CloudRANUtils.getConfigValue(configPath, "tcpIpIP");
            config.tcpIpPort = str2double(CloudRANUtils.getConfigValue(configPath, "tcpIpPort"));
            config.tcpIpTimeout = 5;
            config.senderSoftwareFlowControlIP = CloudRANUtils.getConfigValue(configPath, "senderSoftwareFlowControlIP");
            config.senderSoftwareFlowControlPort = str2double(CloudRANUtils.getConfigValue(configPath, "senderSoftwareFlowControlPort"));
            config.receiverSoftwareFlowControlIP = CloudRANUtils.getConfigValue(configPath, "receiverSoftwareFlowControlIP");
            config.receiverSoftwareFlowControlPort = str2double(CloudRANUtils.getConfigValue(configPath, "receiverSoftwareFlowControlPort"));
        end
    end
end