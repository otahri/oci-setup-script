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
    $oci_cmd iam compartment list --compartment-id $parent_cmp_id --query "data[?\"display-name\"=='$cmp_name'].id | [0]" --raw-output
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
    $oci_cmd iam policy create --compartment-id $cmp_id --name $plcy_name --statements "$plcy_st" --description "Policy for $plcy_name"
}

# -------- main
source "$config_file"

while IFS="$csv_delimiter" read -r app_name snet_cidr; do
    for env in "${env_list[@]}"; do
        app_name=$(echo "$app_name" | tr '[:upper:]' '[:lower:]')
        cmp_app=$(eval echo "$cmp_name")
        snet=$(eval echo "$subnet_name")
        grp_owner=$(eval echo "$group_owner_name")
        grp_user=$(eval echo "$group_user_name")
        plcy_name=$(eval echo "$policy_name")
        plcy_st_owner=$(eval "echo \"$policy_st_owner\"" | sed -e "s/\$app_name/$app_name/g" -e "s/\$env/$env/g" -e 's/\[/\["/g' -e 's/\]/\"]/g')
        plcy_st_user=$(eval "echo \"$policy_st_user\"" | sed -e "s/\$app_name/$app_name/g" -e "s/\$env/$env/g" -e 's/\[/\["/g' -e 's/\]/\"]/g')
        cmp_env_ocid="cmp_${env}_ocid"
        vcn=$(eval echo "$vcn_name")

        new_cmp=$(eval create_cmp $cmp_app "${!cmp_env_ocid}") 
        echo "Compartment Created : $new_camp"

        vcn_ocid=$(eval get_vcn_id_by_name $vcn "${!cmp_env_ocid}")
        echo "vcn ocid of ${!cmp_env_ocid} : $vcn_ocid"
        new_snet=$(eval create_snet $snet "${!cmp_env_ocid}" $vcn_ocid $snet_cidr)
        echo "Subnet Created : $new_snet"

        ownr_grp=$(eval create_grp $grp_owner)
        usr_grp=$(eval create_grp $grp_user)
        echo "User group Created : $usr_grp"
        echo "Owner group Created : $ownr_grp"
        
    done
done < <(tail -n +2 "$data_file")
