% This class stores the configuration values which are related to the
% TCPIP functionality.
classdef TCPIPConfiguration
    properties
        tcpIpIP
        tcpIpPort
        tcpIpTimeout
    end
    methods (Static)
        % This method reads all TCPIP related configuration values from a given
        % config file.
        function config = readConfigValues(configPath)
            config = TCPIPConfiguration;
            config.tcpIpIP = CloudRANUtils.getConfigValue(configPath, "tcpIpIP");
            config.tcpIpPort = str2double(CloudRANUtils.getConfigValue(configPath, "tcpIpPort"));
            config.tcpIpTimeout = 5;
        end
    end
end