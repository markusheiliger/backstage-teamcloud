#!/usr/bin/env bash
bin_dir=`cd "$(dirname "$BASH_SOURCE[0]")"; pwd`
subscription_id="672fab42-9efc-4f65-9b3c-dd6144e4ef60"
resource_group="backstage-$(whoami)"

container_registry="teamcloud.azurecr.io"
container_registry_username="TeamCloud"
container_registry_password=$(az acr credential show --subscription 'b6de8d3f-8477-45fe-8d60-f30c6db2cb06' --resource-group 'TeamCloud-Registry' --name 'TeamCloud' --query 'passwords[0].value' -o tsv)

image_name_dev="teamcloud-dev/tcportal-backstage-$(whoami)"
image_name_rel="teamcloud/tcportal-backstage"
image_tag=$(date +%s)

header() {
	echo ''
	echo '======================================================================================'
	echo $1
	echo '--------------------------------------------------------------------------------------'
	echo ''
}

if [[ " $* " != *" nobuild "* ]]; then

	header "Installing packages ..." \
		&& yarn install 

	header "Transpiling typescript ..." \
		&& yarn tsc

	header "Building packages" ... \
		&& yarn build	

fi

header "Logging into container registry $container_registry ..." \
	&& docker login -u $container_registry_username --password-stdin $container_registry < <(echo $container_registry_password)

header "Building image $image_name_dev:$image_tag ..." \
	&& obsolteImages=$(docker images -q $container_registry/$image_name_dev) \
	&& docker build . -f packages/backend/Dockerfile --tag "$container_registry/$image_name_dev:$image_tag" --tag "$container_registry/$image_name_dev:latest"

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

	header "Deploying to resource group $resource_group ..." \
		&& az deployment group create --subscription $subscription_id --resource-group $resource_group --mode Complete --template-file ./resources/backstage.bicep -o none \
			--parameters registryServer=$container_registry \
			--parameters registryUsername=$container_registry_username \
			--parameters registryPassword=$container_registry_password \
			--parameters containerImage=$image_name_dev:$image_tag \
			--parameters teamcloudOrganizationName=Contoso \
			--parameters azureClientId=d51c023e-dd7e-4ee3-a3ff-01f72bf135a6 \
			--parameters azureClientSecret=sgm7Q~AyyVs4IKeXA9vQQDyjx7bwa0.lv72LR \
		&& echo 'done'

else

	header "Run container $container_registry/$image_name_dev:$image_tag locally ..." \
		&& ( [ ! -z "$(docker ps -a | grep backstage)" ] && docker container rm backstage -f > /dev/null || true ) \
		&& docker run -d --name backstage -p 7007:7007 \
			$container_registry/$image_name_dev:$image_tag \
			node packages/backend --config app-config.yaml --config app-config.local.yaml > /dev/null \
		&& echo "done"		

fi
