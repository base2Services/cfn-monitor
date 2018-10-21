FROM amazonlinux

ENV CWMROOT /opt/base2/cloudwatch-monitoring/
ENV LANG en_US.utf8
SHELL ["/bin/bash", "-c"]
COPY . ${CWMROOT}
RUN gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB && \
    yum install curl which tar gzip procps bzip2 gcc gcc-c++ make zlib-devel openssl-devel -y && \
    curl -sSL https://get.rvm.io | bash -s stable && \
    source /etc/profile.d/rvm.sh && \
    yes "" | rvm install 2.5  && \
    rvm use 2.5 && \
    cd "${CWMROOT}"  && \
    gem install rake cfndsl aws-sdk && \
    rake cfn:test

WORKDIR ${CWMROOT}
