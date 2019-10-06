
ADD asset-yarn.tar.gz /
ADD asset-post-download-dependencies.tar.gz /
COPY asset-node-headers.tar.gz ${HOME}/asset-node-headers.tar.gz

# Copy yarn.lock to be the same than the previous build
ADD asset-yarn.lock ${HOME}/theia-source-code/yarn.lock 

# expand artifact
ADD asset-moxios.tgz /tmp/moxios

RUN \
    # Define node headers
    npm config set tarball ${HOME}/asset-node-headers.tar.gz && \
    # Disable travis script
    echo "#!/usr/bin/env node" > /home/theia-dev/theia-source-code/scripts/prepare-travis \
    # Patch github link to a local link 
    && sed -i -e 's|moxios "git://github.com/stoplightio/moxios#v1.3.0"|moxios "file:///tmp/moxios"|' ${HOME}/theia-source-code/yarn.lock \
    && sed -i -e "s|git://github.com/stoplightio/moxios#v1.3.0|file:///tmp/moxios|" ${HOME}/theia-source-code/yarn.lock \
    # Add offline mode in examples
    && sed -i -e "s|spawnSync('yarn', \[\]|spawnSync('yarn', \['--offline'\]|" ${HOME}/theia-source-code/plugins/foreach_yarn \
    # Disable automatic tests that connect online
    && sed -i -e "s/ && yarn test//" plugins/factory-plugin/package.json 
