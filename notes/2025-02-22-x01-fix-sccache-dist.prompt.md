We want ONLY distributed setup.

* Docker container runs `sccache` scheduler and builder.
* Users compile using it using distributed setup that delegates build to it via IP:PORT (therefore it can be localhost, other docker containers or even other computers).

Update files accordingly.
