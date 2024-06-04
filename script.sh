#! /bin/bash

# -------- usage & args
usage() {
    echo "Usage: $0 --config CONFIG_FILE --data DATA_FILE"
    exit 1
}

if [[ "$#" -ne 4 ]]; then
    usage
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --config)
            config_file="$2"
            shift
            ;;
        --data)
            data_file="$2"
            shift
            ;;
        *)
            usage
            ;;
    esac
    shift
done

if [[ ! -f $config_file ]]; then
    echo "Error: Config file '$config_file' not found!"
    exit 1
fi

if [[ ! -f $data_file ]]; then
    echo "Error: Data file '$data_file' not found!"
    exit 1
fi

# -------- functions
create_cmp() {
    local cmp_name=$1
    local parent_cmp_id=$2
    $oci_cmd iam compartment create --compartment-id $parent_cmp_id --name $cmp_name --description "Compartment $cmp_name" --query data.id --raw-output
}
get_cmp_id_by_name() {
    local cmp_name=$1
    local parent_cmp_id=$2
    $oci_cmd iam compartment list --compartment-id $parent_cmp_id | jq -r ".data[] | select(.name == \"${cmp_name}\") | .id"
}
create_vcn() {
    local cmp_id=$1
    local vcn_name=$2
    local cidr=$3
    $oci_cmd network vcn create --compartment-id $cmp_id --display-name $vcn_name --cidr-block $cidr --query data.id --raw-output
}
create_snet() {
    local name=$1
    local cmp_id=$2
    local vcn_id=$3
    local cidr=$4
    $oci_cmd network subnet create --display-name $name --compartment-id $cmp_id --vcn-id $vcn_id --cidr-block $cidr --query data.id --raw-output
}
get_vcn_id_by_name() {
    local vcn_name=$1
    local cmp_id=$2
    $oci_cmd network vcn list --compartment-id $cmp_id --query "data[?\"display-name\"=='$vcn_name'].id | [0]" --raw-output
}
create_grp() {
    local grp_name=$1
    $oci_cmd iam group create --name $grp_name --description "Group for $grp_name" --query data.id --raw-output
}
create_plcy() {
    local cmp_id=$1
    local plcy_name=$2
    local plcy_st=$3
    $oci_cmd iam policy create --compartment-id $cmp_id --name $plcy_name --statements "$plcy_st" --description "Policy for $plcy_name" --query data.id --raw-output
}
add_plcy_st() {
    local plcy_id=$1
    local new_st=$2
    local policy=$($oci_cmd iam policy get --policy-id $plcy_id)
    local existing_statements=$(echo $policy | jq -r '.data.statements | @json')
    local statements=$(echo $existing_statements | jq --argjson new "$new_st" '. + $new')
    $oci_cmd iam policy update --policy-id $plcy_id --statements "$statements" --version-date "" --force
}


# -------- main
source "$config_file"

for env in "${env_list[@]}"; do
    cmp_env_ocid="cmp_${env}_ocid"
    cmp_ocid=${!cmp_env_ocid}
    plcy_name=$(eval echo "$policy_name")
    new="true"

    while IFS="$csv_delimiter" read -r app_name snet_cidr; do
        app_name=$(echo "$app_name" | tr '[:upper:]' '[:lower:]')
        cmp_app=$(eval echo "$cmp_name")
        snet=$(eval echo "$subnet_name")
        grp_owner=$(eval echo "$group_owner_name")
        grp_user=$(eval echo "$group_user_name")
        plcy_st_owner=$(eval "echo \"$policy_st_owner\"" | sed -e "s/\$app_name/$app_name/g" -e "s/\$env/$env/g" -e 's/\[/\["/g' -e 's/\]/\"]/g' -e 's/\,/\","/g')
        plcy_st_user=$(eval "echo \"$policy_st_user\"" | sed -e "s/\$app_name/$app_name/g" -e "s/\$env/$env/g" -e 's/\[/\["/g' -e 's/\]/\"]/g' -e 's/\,/\","/g')
        vcn=$(eval echo "$vcn_name")
        cmp_env_ocid="cmp_${env}_ocid"

        new_cmp=$(eval create_cmp $cmp_app "${!cmp_env_ocid}") 

        shrd_ntw_cmp_id=$(eval get_cmp_id_by_name $cmp_shared_network "${!cmp_env_ocid}")

        vcn_ocid=$(eval get_vcn_id_by_name $vcn $shrd_ntw_cmp_id)
        echo "vcn ocid of $vcn : $vcn_ocid"
        new_snet=$(eval create_snet $snet $shrd_ntw_cmp_id $vcn_ocid $snet_cidr)
        echo "Subnet Created : $new_snet"

        ownr_grp=$(eval create_grp $grp_owner)
        usr_grp=$(eval create_grp $grp_user)
        echo "User group Created : $usr_grp"
        echo "Owner group Created : $ownr_grp"

        if [ "$new" == "true" ]; then
            plcy_id=$(create_plcy $cmp_ocid $plcy_name "$plcy_st_owner")
            add_plcy_st $plcy_id "$plcy_st_user"
        else
            add_plcy_st $plcy_id "$plcy_st_owner"
            add_plcy_st $plcy_id "$plcy_st_user"
        fi
        new="false"
    
    done < <(tail -n +2 "$data_file")
done

