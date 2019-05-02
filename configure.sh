#!/usr/bin/env bash

set -eu -o pipefail

# prints a section header
function header() {
    local title=$1
    local rest="========================================================================"
    echo
    echo "===[ ${title} ]${rest:${#title}}"
    echo
}

# Fixes tha lack of the `realpath` tool in OS X.
if [ ! $(which realpath) ]; then
    function realpath() {
        python -c 'import os, sys; print os.path.realpath(sys.argv[1])' "${1%}"
    }
fi

if [[ $# -ne 1 ]] ; then
    echo 'Specify pom.xml'
    exit 0
fi

HERE="$(pwd)"
PROJECT_POM_PATH="$(realpath ${HERE}/$1)"
echo "PROJECT_POM_PATH=${PROJECT_POM_PATH}"

header "PROJECT ==>"
GROUP_ID="$(xmllint --xpath '/*[local-name()="project"]/*[local-name()="groupId"]/text()' ${PROJECT_POM_PATH})"
echo "GROUP_ID=${GROUP_ID}"

ARTIFACT_NAME="$(xmllint --xpath '/*[local-name()="project"]/*[local-name()="artifactId"]/text()' ${PROJECT_POM_PATH})"
echo "ARTIFACT_NAME=${ARTIFACT_NAME}"

ARTIFACT_VERSION="$(xmllint --xpath '/*[local-name()="project"]/*[local-name()="version"]/text()' ${PROJECT_POM_PATH})"
echo "ARTIFACT_VERSION=${ARTIFACT_VERSION}"

header "<== PROJECT"



header "GETTING PATHS ==>"

EJB_GIT="${HERE}/exonum-java-binding"
echo "EJB_GIT=${EJB_GIT}"

# Use an already set JAVA_HOME, or infer it from java.home system property.
#
# Unfortunately, a simple `which java` will not work for some users (e.g., jenv),
# hence this a bit complex thing.
JAVA_HOME="${JAVA_HOME:-$(java -XshowSettings:properties -version 2>&1 > /dev/null | grep 'java.home' | awk '{print $3}')}/"
echo "JAVA_HOME=${JAVA_HOME}"

# Find the directory containing libjvm (the relative path has changed in Java 9)
JVM_LIB_PATH="$(find ${JAVA_HOME} -type f -name libjvm.* | xargs -n1 dirname)"
echo "JVM_LIB_PATH=${JVM_LIB_PATH}"

RUST_LIB_DIR="$(rustup run 1.32.0 rustc --print sysroot)/lib"
echo "RUST_LIB_DIR=${RUST_LIB_DIR}"

EJB_ROOT="${EJB_GIT}/exonum-java-binding"
echo "EJB_ROOT=${EJB_ROOT}"

EJB_LIBPATH="${EJB_ROOT}/core/rust/target/debug"
echo "EJB_LIBPATH=${EJB_LIBPATH}"

EJB_APP_DIR="${EJB_ROOT}/core/rust/ejb-app"
echo "EJB_APP_DIR=${EJB_APP_DIR}"

export LD_LIBRARY_PATH="$JVM_LIB_PATH:$RUST_LIB_DIR:$EJB_LIBPATH"
echo "LD_LIBRARY_PATH=${LD_LIBRARY_PATH}"

EJB_LOG_CONFIG_PATH="${HERE}/empty/log4j2.xml"
echo "EJB_LOG_CONFIG_PATH=${EJB_LOG_CONFIG_PATH}"

EJB_CLASSPATH="${HERE}/empty/target/${ARTIFACT_NAME}-${ARTIFACT_VERSION}-jar-with-dependencies.jar"
echo "EJB_CLASSPATH=${EJB_CLASSPATH}"

MANIFEST_PATH="${EJB_APP_DIR}/Cargo.toml"
echo "MANIFEST_PATH=${MANIFEST_PATH}"

TESTNET="${HERE}/testnet"
echo "TESTNET=${TESTNET}"

EJB_POM_PATH="${EJB_GIT}/pom.xml"
echo "EJB_POM_PATH=${EJB_POM_PATH}"

header "<== GETTING PATHS"



header "GETTING Exonum-Java-Binding ==>"

rm -rf $EJB_GIT

git clone https://github.com/exonum/exonum-java-binding.git

cd $EJB_GIT
git checkout tags/ejb/v0.5.0 # Use EJB 0.5 version
source ${EJB_ROOT}/tests_profile
mvn clean install -f $EJB_POM_PATH

header "<== GETTING Exonum-Java-Binding"



header "COMPILING Exonum-Java-Binding Application ==>"

cd $EJB_APP_DIR
cargo build

header "<== COMPILING Exonum-Java-Binding Application ==>"



header "GENERATE COMMON CONFIG ==>"

rm -rf ${TESTNET}
mkdir ${TESTNET}

cargo run --manifest-path ${MANIFEST_PATH} -- generate-template --validators-count=1 "${TESTNET}/common.toml"

header "<== GENERATE COMMON CONFIG"



header "GENERATE NODE CONFIG ==>"

cargo run --manifest-path ${MANIFEST_PATH} -- generate-config "${TESTNET}/common.toml" "${TESTNET}/pub.toml" "${TESTNET}/sec.toml" \
 --ejb-classpath $EJB_CLASSPATH \
 --ejb-libpath $EJB_LIBPATH \
 --ejb-log-config-path $EJB_LOG_CONFIG_PATH \
 --peer-address 127.0.0.1:5400

header "<== GENERATE NODE CONFIG"



header "FINALIZE NODE CONFIG ==>"

cargo run --manifest-path ${MANIFEST_PATH} -- finalize "${TESTNET}/sec.toml" "${TESTNET}/node.toml" \
 --ejb-module-name "${GROUP_ID}.ServiceModule" \
 --ejb-port 6000 \
 --public-configs "${TESTNET}/pub.toml"

header "<== FINALIZE NODE CONFIG"



header "GENERATE START SCRIPT ==>"

RUN="${HERE}/empty/run.sh"
chmod +x $RUN
echo "export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}" > $RUN
echo "mvn clean install -f ${PROJECT_POM_PATH}" >> $RUN
echo "cargo run --manifest-path ${MANIFEST_PATH} -- run -d ${TESTNET}/db -c ${TESTNET}/node.toml --public-api-address 0.0.0.0:3000" >> $RUN
echo "Execute ${RUN}"

header "<== GENERATE START SCRIPT"

header "<== CONFIGURATION IS COMPLETE ==>"
