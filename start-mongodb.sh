#!/bin/sh

# Map input values from the GitHub Actions workflow to shell variables
MONGODB_VERSION=$1
MONGODB_REPLICA_SET=$2
MONGODB_PORT=$3

DOCKER_NETWORK=$4


if [ -z "$MONGODB_VERSION" ]; then
  echo ""
  echo "Missing MongoDB version in the [mongodb-version] input. Received value: $MONGODB_VERSION"
  echo ""

  exit 2
fi


echo ""
echo "############################################"
echo "Removing existing [mongodb] Docker container"
echo "############################################"

if [ "$(docker ps -aq -f name=mongodb)" ]; then
    docker stop mongodb
    docker rm mongodb
    echo "Removed existing [mongodb] docker container."
else
  echo "Nothing to clean up. No container named [mongodb] running."
fi


if [ -z "$MONGODB_REPLICA_SET" ]; then
  echo ""
  echo "#############################################"
  echo "Starting single-node instance, no replica set"
  echo "  - port [$MONGODB_PORT]"
  echo "  - version [$MONGODB_VERSION]"
  echo "  - docker-network [$DOCKER_NETWORK]"
  echo "#############################################"


  if [ ! -z "$DOCKER_NETWORK" ]; then
    docker run --name mongodb --publish $MONGODB_PORT:$MONGODB_PORT --detach --network $DOCKER_NETWORK mongo:$MONGODB_VERSION --port $MONGODB_PORT
  else
    docker run --name mongodb --publish $MONGODB_PORT:$MONGODB_PORT --detach mongo:$MONGODB_VERSION --port $MONGODB_PORT
  fi

  docker ps
  echo ""
  echo "#############################################"
  echo ""
  docker inspect mongodb

  return
fi


echo ""
echo "###########################################"
echo "Starting MongoDB as single-node replica set"
echo "  - port [$MONGODB_PORT]"
echo "  - version [$MONGODB_VERSION]"
echo "  - replica set [$MONGODB_REPLICA_SET]"
echo "  - docker-network [$DOCKER_NETWORK]"
echo "###########################################"


if [ ! -z "$DOCKER_NETWORK" ]; then
  docker run --name mongodb --publish $MONGODB_PORT:$MONGODB_PORT --detach --network $DOCKER_NETWORK mongo:$MONGODB_VERSION --port $MONGODB_PORT --replSet $MONGODB_REPLICA_SET
else
  docker run --name mongodb --publish $MONGODB_PORT:$MONGODB_PORT --detach mongo:$MONGODB_VERSION --port $MONGODB_PORT --replSet $MONGODB_REPLICA_SET
fi

echo ""
echo "#########################################"
echo "Waiting for MongoDB to accept connections"
echo "#########################################"

sleep 1
TIMER=0
until docker exec --tty mongodb mongo --port $MONGODB_PORT --eval "db.serverStatus()" # &> /dev/null
do
  sleep 1
  echo "."
  TIMER=$((TIMER + 1))

  if [[ $TIMER -eq 20 ]]; then
    echo "MongoDB did not initialize within 20 seconds. Exiting."
    exit 2
  fi
done


echo ""
echo "#########################################"
echo "Initiating replica set [$MONGODB_REPLICA_SET]"
echo "#########################################"

echo "RS configuration -->"
echo "
  {
    \"_id\": \"$MONGODB_REPLICA_SET\",
    \"members\": [ {
       \"_id\": 0,
      \"host\": \"localhost:$MONGODB_PORT\"
    } ]
  })
"

echo ""

docker exec --tty mongodb mongo --port $MONGODB_PORT --eval "
  rs.initiate({
    \"_id\": \"$MONGODB_REPLICA_SET\",
    \"members\": [ {
       \"_id\": 0,
      \"host\": \"localhost:$MONGODB_PORT\"
    } ]
  })
"

echo "Success! Initiated replica set [$MONGODB_REPLICA_SET]"

echo ""
echo "##############################################"
echo "Checking replica set status [$MONGODB_REPLICA_SET]"
echo "##############################################"

docker exec --tty mongodb mongo --port $MONGODB_PORT --eval "
  rs.status()
"
