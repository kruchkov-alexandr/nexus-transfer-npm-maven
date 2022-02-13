#!/bin/bash
# Description: transfer maven/npm libs between repos
# Requirements: curl, jq, bash 3+
# happypath:
# 1) get all artifact's url from Nexus API and save to txt file
# 2) get download links from txt file, download files by curl and save to temp directory
# 3) transform url links in txt file (except npm)
# 4) upload files to new nexus repo by curl
# 5) cleanup
echo "start"
############## variables ##############################################
FROM_CREDENTIALS=%LOGIN%:%PASSWORD%
TO_CREDENTIALS=%LOGIN%:%PASSWORD%
FROM_REPO=src-npm-lib
TO_REPO=dest-npm-lib
NEXUS="nexus.com"
#######################################################################

# predefined variables
NEXUS_API="${NEXUS}/service/rest/v1/components?repository"
NEXUS_API_WITH_CREDENTIALS=https://"${FROM_CREDENTIALS}"@"${NEXUS_API}"
URL_LIST=links.txt

# create file
rm -f ${URL_LIST}
touch ${URL_LIST} || true
# read from old repo and save all downloadlinks to ${URL_LIST} file
while DATA=$(curl --insecure -ss "${NEXUS_API_WITH_CREDENTIALS}=${FROM_REPO}${continuationToken}"); do
    [[ ${DATA} == "" ]] && exit 1
    continuationToken=$(echo "$DATA" | jq -r .continuationToken)
    echo "$DATA" | jq -rc '.items| .[].assets| .[].downloadUrl' >>${URL_LIST}
    [[ ${continuationToken} != "null" ]] && continuationToken="&continuationToken=${continuationToken}" || break
done

# OPTIONAL! cleanup, delete extra links from  ${URL_LIST} file
# sed -i '/yaml$/d' ${URL_LIST}
# cat "${URL_LIST}" | grep vtb-ib > ${URL_LIST}

# read ${URL_LIST} file with links, download files from old repo and upload to new repo
while read -r line; do
    # define filename for downloading
    filename=$(echo "$line" | sed "s/https:\/\/${NEXUS}\/repository\/$FROM_REPO\///i" |
        sed 's/\// /g' | rev | cut -d " " -f1 | rev)
    # download file from old repo
    curl -u ${FROM_CREDENTIALS} \
        --insecure \
        -ss \
        -X GET "${line}" \
        -o /tmp/"${filename}"
    # transform download link to upload link
    repo=$(echo "$line" | sed "s/$filename//g" | sed "s/${FROM_REPO}/${TO_REPO}/g")
    # upload file to new nexus repo
    if [[ $FROM_REPO = *"npm"* ]]; then
        curl -u ${TO_CREDENTIALS} \
            --insecure \
            -ss \
            -F "npm.asset=@/tmp/${filename}" \
            "https://${NEXUS_API}=${TO_REPO}"
    else
        curl -u ${TO_CREDENTIALS} \
            --insecure \
            -ss \
            --upload-file /tmp/"${filename}" "$repo"
    fi
    rm /tmp/${filename}
done <${URL_LIST}

# cleanup
rm ${URL_LIST}
echo "finish"
