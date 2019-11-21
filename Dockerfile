FROM madhacking/gentoo-testrunner:latest

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/usr/local/sbin/test-runner"]
