const { dynamoClient,
  TABLE_NAME,
  getParks,
  getFacilities,
  sendResponse,
  logger,
  UpdateItemCommand } = require('/opt/baseLayer');
const { getCurrentDisplayNameById } = require('/opt/dataRegisterLayer');

// This function queries the bcparks database for park names. 
// If any park names have changed, the db item is updated with the new name. 
exports.handler = async (event, context) => {
  logger.info('Updating current park names.');
  try {
    // get all parks in the system.
    const parks = await getParks();
    for (const park of parks) {
      const currentName = await getCurrentDisplayNameById(park.orcs);
      if (currentName !== park.name) {
        await updateDisplayName(park, currentName);
      }
    }
    return sendResponse(200, {}, context)
  } catch (err) {
    logger.error(err);
    return sendResponse(500, err, context)
  }
}

async function updateDisplayName(park, newName) {
  const oldName = park.name;
  try {
    // update park name
    const updatePark = {
      TableName: TABLE_NAME,
      Key: {
        pk: { S: park.pk },
        sk: { S: park.sk }
      },
      ExpressionAttributeValues: {
        ':name': { S: newName }
      },
      ExpressionAttributeNames: {
        '#name': 'name'
      },
      UpdateExpression: 'SET #name = :name',
      ReturnValues: 'ALL_NEW'
    }

    const command = new UpdateItemCommand(updatePark);
    dynamoClient.send(command);

    // update park name in facilities
    const facilities = await getFacilities(park.orcs);

    for (const facility of facilities) {
      const updateFacility = {
        TableName: TABLE_NAME,
        Key: {
          pk: { S: facility.pk },
          sk: { S: facility.sk }
        },
        ExpressionAttributeValues: {
          ':parkName': { S: newName },
        },
        UpdateExpression: `SET parkName = :parkName`,
        ReturnValues: 'ALL_NEW'
      }

      const command = new UpdateItemCommand(updateFacility);
      dynamoClient.send(command);
    }

    logger.info(`Park name updated for ${park.orcs}: ${oldName} is now ${newName}`);

  } catch (err) {
    throw err;
  }
}
