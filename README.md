# LocalEGA-inbox
OpenSSH dropbox, with credentials from CentralEGA and RabbitMQ notifications for file system events


To build the docker image, use:

	# Create the "lega" group
	getent group lega || groupadd -g 1001 lega # adjust the number if needed

	# Build the image (using the above group, for access permissions)
	make latest

You can run a test instance (not connected to a local broker) with:

	docker-compose up -d

However, you first need to get credentials from Central EGA, and add them to the compose file.
