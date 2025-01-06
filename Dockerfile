# Use the official linuxserver/code-server base image
FROM linuxserver/code-server:latest

# Get the Linux version
RUN cat /etc/os-release

# Set environment variables
ENV PASSWORD=123

# Expose the port that code-server will run on
EXPOSE 8443

# Install PowerShell
RUN apt-get update && \
    apt-get install -y wget apt-transport-https software-properties-common && \
    wget https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/powershell-7.4.6-linux-arm64.tar.gz && \
    mkdir -p /opt/microsoft/powershell/7 && \
    tar -xvf powershell-7.4.6-linux-arm64.tar.gz -C /opt/microsoft/powershell/7 && \
    chmod +x /opt/microsoft/powershell/7/pwsh && \
    ln -s /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh && \
    rm -f powershell-7.4.6-linux-arm64.tar.gz && \
    apt-get update 


