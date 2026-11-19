# The image Reynard is built in on Linux (tools/linux/README.md): the open Swift toolchain (swiftc and
# clang 21 for the app shell) plus what Firefox's own build wants on the build machine. It holds nothing
# of Apple's: the iOS SDK is mounted at run time from wherever the host keeps it (tools/linux/rx).
FROM swift:6.4-noble
COPY provision.sh /tmp/provision.sh
RUN sh /tmp/provision.sh && rm /tmp/provision.sh
ENV RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo PATH=/opt/cargo/bin:$PATH
