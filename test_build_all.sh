#!/usr/bin/env bash
addon_dir_path="Interface/AddOns/"
# ./packager/release.sh -r ${WOW_ROOT}/__classic_era__/Interface\AddOns/CoolLine -e -g classic -d -l -z
# ./packager/release.sh -r ${WOW_ROOT}/__classic__/Interface/AddOns/CoolLine     -e -g bcc     -d -l -z
# ./packager/release.sh -r ${WOW_ROOT}/__retail__/Interface/AddOns/CoolLine      -e -g retail  -d -l -z

./packager/release.sh -r "${WOW_ROOT_LINUX}/_classic_era_/${addon_dir_path}" -g classic -d -l -z
./packager/release.sh -r "${WOW_ROOT_LINUX}/_classic_/${addon_dir_path}"     -g bcc     -d -l -z
./packager/release.sh -r "${WOW_ROOT_LINUX}/_retail_/${addon_dir_path}"      -g retail  -d -l -z
