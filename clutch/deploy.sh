#!/usr/bin/env bash
bin_dir=`cd "$(dirname "$BASH_SOURCE[0]")"; pwd`
subscription_id="672fab42-9efc-4f65-9b3c-dd6144e4ef60"
portal_type=$(basename "$bin_dir")
portal_identity="caaf8175-97d0-4dc2-ab11-d26a631096db"
resource_group="$portal_type-$(whoami)"

container_registry="teamcloud.azurecr.io"
container_registry_username="TeamCloud"
container_registry_password=$(az acr credential show --subscription 'b6de8d3f-8477-45fe-8d60-f30c6db2cb06' --resource-group 'TeamCloud-Registry' --name 'TeamCloud' --query 'passwords[0].value' -o tsv)

image_name_dev="teamcloud-dev/tcportal-$portal_type-$(whoami)"
image_name_rel="teamcloud/tcportal-$portal_type"
image_tag=$(date +%s)

header() {
	echo ''
	echo '======================================================================================'
	echo $1
	echo '--------------------------------------------------------------------------------------'
	echo ''
}

if [[ " $* " != *" nobuild "* ]]; then

	header "Build source ..." \
		&& echo 'done'

fi

header "Logging into container registry $container_registry ..." \
	&& docker login -u $container_registry_username --password-stdin $container_registry < <(echo $container_registry_password)

header "Building image $image_name_dev:$image_tag ..." \
	&& obsolteImages=$(docker images -q $container_registry/$image_name_dev) \
	&& docker build . --tag "$container_registry/$image_name_dev:$image_tag" --tag "$container_registry/$image_name_dev:latest"

[ ! -z "$obsolteImages" ] \
	&& header "Cleaning up obsolete images ..." \
	&& (docker image rm --force $obsolteImages || true) \
	&& echo 'done'

header "Pushing image $image_name_dev:$image_tag and :latest ..." \
	&& docker push "$container_registry/$image_name_dev:$image_tag" \
	&& docker push "$container_registry/$image_name_dev:latest" 	

[ "$(az group exists --subscription $subscription_id --name $resource_group)" == "false" ] \
	&& header "Creating resource group $resource_group ..." \
	&& az group create --subscription $subscription_id --name $resource_group --location eastus -o none \
	&& echo 'done'

if [[ " $* " == *" release "* ]]; then

	header "Releasing image $container_registry/$image_name_dev:latest ..." \
		&& docker tag $container_registry/$image_name_dev:latest $container_registry/$image_name_rel:latest \
		&& docker push $container_registry/$image_name_rel:latest

elif [[ " $* " == *" deploy "* ]]; then

	if [[ " $* " == *" reset "* ]] && [[ "$(az group exists --subscription $subscription_id --name $resource_group)" == "true" ]]; then

		header "Resetting resource group $resource_group ..." \
			&& az group delete --subscription $subscription_id --name $resource_group --yes -o none \
			&& az group create --subscription $subscription_id --name $resource_group --location eastus -o none \
			&& echo 'done'

	fi 

	header "Deploying to resource group $resource_group ..." \
		&& az deployment group create --subscription $subscription_id --resource-group $resource_group --mode Complete --template-file ./resources/portal.bicep --query 'properties.outputs' \
			--parameters registryServer=$container_registry \
			--parameters registryUsername=$container_registry_username \
			--parameters registryPassword=$container_registry_password \
			--parameters containerImage=$image_name_dev:$image_tag \
			--parameters teamcloudOrganizationName=$(whoami) \
			--parameters azureClientId=$portal_identity \
			--parameters azureClientSecret=$(az ad app credential reset --id $portal_identity --query password -o tsv) \
		&& echo 'done'

else

	header "Run container $container_registry/$image_name_dev:$image_tag locally ..." \
		&& ( [ ! -z "$(docker ps -a | grep $porta_type)" ] && docker container rm $porta_type -f > /dev/null || true ) \
		&& docker run -d --name $porta_type -p 7007:7007 \
			--env teamcloudOrganizationName=$(whoami) \
			--env azureClientId=$portal_identity \
			--env azureClientSecret=$(az ad app credential reset --id $portal_identity --query password -o tsv) \
			$container_registry/$image_name_dev:$image_tag \
			node packages/backend --config app-config.yaml --config app-config.local.yaml > /dev/null \
		&& echo "done"		

fi
