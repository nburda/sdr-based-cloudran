classdef TCPIPConfiguration
    properties
        tcpIpIP
        tcpIpPort
        tcpIpTimeout
    end
    methods (Static)
        function config = readConfigValues(configPath)
            config = TCPIPConfiguration;
            config.tcpIpIP = CloudRANUtils.getConfigValue(configPath, "tcpIpIP");
            config.tcpIpPort = str2double(CloudRANUtils.getConfigValue(configPath, "tcpIpPort"));
            config.tcpIpTimeout = 5;
        end
    end
end