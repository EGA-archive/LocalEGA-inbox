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

You then connect to the running instance with:

	sftp -P 2222 username@localhost # adjust the port if needed, including in your compose file

On success, you should get a prompt such as:

	Welcome to Local EGA Demo instance
	Connected to localhost.
	sftp>
