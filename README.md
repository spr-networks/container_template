# container_template
Ubuntu 23.04 Dockerfile Template for SPR Containers

## About

This container will help minimize the size of deployed containers by providing a common layer for SPR containers to use. 
Without a common container, it becomes more difficult to manage thigns like cleaning up articts from apt-get that are not needed,
as well as updating each docker file when the common packages are updated.
