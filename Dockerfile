FROM debian:stretch AS builder
MAINTAINER "Cédric Verstraeten" <hello@cedric.ws>

ARG APP_ENV=master
ENV APP_ENV ${APP_ENV}
#ARG PHP_VERSION=7.1
ARG FFMPEG_VERSION=3.1

#################################
# Surpress Upstart errors/warning

RUN dpkg-divert --local --rename --add /sbin/initctl
RUN ln -sf /bin/true /sbin/initctl

#############################################
# Let the container know that there is no tty

ENV DEBIAN_FRONTEND noninteractive

#########################################
# Update base image
# Add sources for latest nginx and cmake
# Install software requirements

RUN apt-get update && apt-get install -y apt-transport-https wget lsb-release \
software-properties-common libssl-dev git supervisor curl \
subversion libcurl4-openssl-dev cmake dh-autoreconf autotools-dev autoconf automake gcc g++ \
build-essential libtool make nasm zlib1g-dev tar apt-transport-https \
ca-certificates

RUN wget http://www.nasm.us/pub/nasm/releasebuilds/2.13.01/nasm-2.13.01.tar.bz2 && \
tar xjvf nasm-2.13.01.tar.bz2  && \
cd nasm-2.13.01  && \
./autogen.sh  && \
./configure  && \
make  && \
make install

RUN apt-get install nasm

############################
# Clone and build x264

RUN git clone https://code.videolan.org/videolan/x264 /tmp/x264 && \
	cd /tmp/x264 && \
	git checkout df79067c && \
	./configure --prefix=/usr --enable-shared --enable-static --enable-pic && make && make install

############################
# Clone and build ffmpeg

# Get latest userland tools and build. Clean up unused stuff at the end
RUN cd \
    && git clone --depth 1 https://github.com/raspberrypi/userland.git \
    && cd userland \
		&& sed -i 's/sudo//g' ./buildme \
    && ./buildme \
    && rm -rf ../userland
RUN apt-get install libomxil-bellagio-dev -y
RUN apt-get install -y pkg-config && git clone https://github.com/FFmpeg/FFmpeg && \
	cd FFmpeg && git checkout remotes/origin/release/${FFMPEG_VERSION} && \
	./configure --enable-nonfree --enable-libx264 --enable-gpl && make && \
    make install && \
    cd .. && rm -rf FFmpeg

############################
# Clone and build machinery

RUN git clone https://github.com/kerberos-io/machinery /tmp/machinery && \
    cd /tmp/machinery && git checkout c8b551b12e82041a49275b2239f672ecc34700e6 && \
    mkdir build && cd build && \
    cmake .. && make && make check && make install && \
    rm -rf /tmp/machinery && \
    chown -Rf www-data.www-data /etc/opt/kerberosio && \
    chmod -Rf 777 /etc/opt/kerberosio/config

#####################
# Clone and build web
# REMOVED
#####################

# Let's create a /dist folder containing just the files necessary for runtime.
# Later, it will be copied as the / (root) of the output image.

WORKDIR /dist
RUN mkdir -p ./etc/opt && cp -r /etc/opt/kerberosio ./etc/opt/
RUN mkdir -p ./usr/bin && cp /usr/bin/kerberosio ./usr/bin/
RUN mkdir -p ./var/www && cp -r /var/www/web ./var/www/
RUN test -d /opt/vc && mkdir -p ./usr/lib && cp -r /opt/vc/lib/* ./usr/lib/ || echo "not found"
RUN cp /usr/local/bin/ffmpeg ./usr/bin/ffmpeg

# Optional: in case your application uses dynamic linking (often the case with CGO),
# this will collect dependent libraries so they're later copied to the final image
# NOTE: make sure you honor the license terms of the libraries you copy and distribute
RUN ldd /usr/bin/kerberosio | tr -s '[:blank:]' '\n' | grep '^/' | \
    xargs -I % sh -c 'mkdir -p $(dirname ./%); cp % ./%;'

FROM debian:stretch-slim

#################################
# Copy files from previous images

COPY --chown=0:0 --from=builder /dist /

#RUN apt-get -y update && apt-get install -y apt-transport-https wget curl lsb-release && \
#wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg && \
#echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list && apt update -y

####################################
# ADD supervisor and STARTUP script

RUN apt-get install -y supervisor && mkdir -p /var/log/supervisor/
ADD ./supervisord.conf /etc/supervisord.conf
ADD ./run.sh /run.sh
RUN chmod 755 /run.sh && chmod +x /run.sh

######################
# INSTALL Nginx
######################
# INSTALL PHP
#
# COPY template folder

# Copy the config template to filesystem
ADD ./config /etc/opt/kerberosio/template
#ADD ./webconfig /var/www/web/template

########################################################
# Exposing web on port 80 and livestreaming on port 8889

EXPOSE 8889
#EXPOSE 80

############################
# Volumes

VOLUME ["/etc/opt/kerberosio/capture"]
VOLUME ["/etc/opt/kerberosio/config"]
VOLUME ["/etc/opt/kerberosio/logs"]
#VOLUME ["/var/www/web/config"]

CMD ["bash", "/run.sh"]
