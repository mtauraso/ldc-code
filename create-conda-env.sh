#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

FEW_GIT_URL="https://github.com/BlackHolePerturbationToolkit/FastEMRIWaveforms.git"
FEW_GIT_BRANCH="master"

# Note: Download code for LDC only works for gdocs urls that hand you a zip file
LDC_URL="https://docs.google.com/uc?export=download&id=1lx3KbAGucKiGI7mGSG-YWj5J4cTSmIlg"
# Change this function to alter download/unzip characteristics
function download_and_unzip_ldc() {
    # Assumes we can dump the intermediate downloaded file in pwd
    LDC_URL=$1
    LDC_DIR=$2

    LDC_ZIP="./LDC-master.zip"

    if [[ ! -f ${LDC_ZIP} ]]; then
        gdown ${LDC_URL} -O ${LDC_ZIP}

        if [[ -d ${LDC_DIR} ]]; then
            rm -rf ${LDC_DIR}
        fi
    fi

    if [[ ! -d ${LDC_DIR} ]]; then
        unzip -q ${LDC_ZIP}
    fi
}


# Only use mamba if we can find it, warn the user
MAMBA_VERSION="$(mamba --version || echo notfound)"
CONDA_VERSION="$(conda --version || echo notfound)"
if [[ $MAMBA_VERSION != "notfound" ]]; then
    CONDA_COMMAND="mamba"
elif [[ $CONDA_VERSION != "notfound" ]]; then
    CONDA_COMMAND="conda"
    echo "Found conda but not mamba. Highly recommend you use mamba for speed of environment creation."
else
    echo "Cannot find conda or mamba. Please put one of them on the path"
    exit 1
fi


# Get the directory of the current script
SOURCE_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# We use build-conda as the staging area
BUILD_DIR="${SOURCE_DIR}/build"

# 0 unless we need to rebuild conda env (Takes a long time)
REBUILD_CONDA=$(cmp --silent -- "${BUILD_DIR}/environment.yml" "${SOURCE_DIR}/environment.yml"; echo $?)

mkdir -p ${BUILD_DIR}

pushd ${BUILD_DIR}
        CONDA_ENV_DIR="${BUILD_DIR}/conda-env"

        if [[ $REBUILD_CONDA -ne 0 ]]; then
                CONDA_ENV_YML="${SOURCE_DIR}/environment.yml"

                # Build a brand-new conda env.
                rm -rf ${CONDA_ENV_DIR}
                rm -rf ${BUILD_DIR}/environment.yml

                mamba env create -f ${CONDA_ENV_YML} -p ${CONDA_ENV_DIR}

                cp ${CONDA_ENV_YML} "${BUILD_DIR}/environment.yml"
        fi
        # Activate our conda env
        # One of conda's activation scripts can't work in strict nounset
        # When there's a compiler in the environment
        set +o nounset
        eval "$(command conda shell.bash activate ${CONDA_ENV_DIR})"
        set -o nounset


    # Download FEW for emri generation and build in the conda env
    FEW_DIR=${BUILD_DIR}/FastEMRIWaveforms
    if [[ ! -d ${FEW_DIR} ]]; then
        git clone ${FEW_GIT_URL} --branch ${FEW_GIT_BRANCH}
    fi
    pushd $FEW_DIR
        python setup.py install
    popd

    # Download the zip file if needed? (docs url is mega-weird, maybe punt on this until you can just do a git checkout)
    LDC_DIR="${BUILD_DIR}/LDC-master"
    download_and_unzip_ldc ${LDC_URL} ${LDC_DIR}

    pushd ${LDC_DIR}
        # This should hopefully be 90% a no-op
        pip install -r requirements.txt

        # edit setup.cfg so it looks at conda rather than system for includes
        cat << EOF > setup.cfg
[build_ext]
include_dirs=${CONDA_ENV_DIR}/include
library_dirs=${CONDA_ENV_DIR}/lib
EOF

        # liborbit's setup.py is very persnickty about how to give it include files
        # Since it wants to look in python's prefix path (which is our conda env), 
        # we symlink the header files it needs there from their conda locations.
        ln -sf ${CONDA_ENV_DIR}/include/python3.7m/lisaconstants/lisaconstants.h ${CONDA_ENV_DIR}/include/lisaconstants.h
        ln -sf ${CONDA_ENV_DIR}/include/python3.7m/lisaconstants/lisaconstants.hpp ${CONDA_ENV_DIR}/include/lisaconstants.hpp

        python setup.py build_liborbits install
    popd
popd #${BUILD_DIR}