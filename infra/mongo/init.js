// Job d'initialisation MongoDB du microservice Assistant (doc/api/mongo/choix-odm-mongodb.md).
//
// Crée les collections avec leur validateur et leurs index. Rejouable : une collection
// existante voit son validateur mis à jour (collMod), un index identique n'est pas recréé,
// un index TTL dont la durée change est modifié par collMod.
// Ne supprime jamais d'index (pas de syncIndexes).
//
// Usage : mongosh "<url>" --quiet --file infra/mongo/init.js
// Variable d'environnement : MONGO_DB (défaut : assistant).

const dbName = process.env.MONGO_DB || 'assistant';
const target = db.getSiblingDB(dbName);

const NINETY_DAYS = 60 * 60 * 24 * 90;

const VALIDATORS = {
  conversations: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['userId', 'status', 'messageCount', 'summarizedUpTo', 'lastMessageAt', 'createdAt', 'updatedAt'],
      properties: {
        userId: { bsonType: 'string', minLength: 1 },
        title: { bsonType: 'string', maxLength: 50 },
        tripId: { bsonType: 'string' },
        status: { enum: ['active', 'archived'] },
        summary: { bsonType: 'string' },
        summarizedUpTo: { bsonType: ['int', 'long', 'double'], minimum: 0 },
        messageCount: { bsonType: ['int', 'long', 'double'], minimum: 0 },
        lastMessageAt: { bsonType: 'date' },
        createdAt: { bsonType: 'date' },
        updatedAt: { bsonType: 'date' },
      },
    },
  },
  messages: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['conversationId', 'userId', 'role', 'content', 'createdAt'],
      properties: {
        conversationId: { bsonType: 'objectId' },
        userId: { bsonType: 'string', minLength: 1 },
        role: { enum: ['user', 'assistant'] },
        content: { bsonType: 'string', minLength: 1 },
        modelVersion: { bsonType: 'string' },
        createdAt: { bsonType: 'date' },
      },
    },
  },
  analytics_events: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['userId', 'type', 'occurredAt', 'receivedAt'],
      properties: {
        userId: { bsonType: 'string', minLength: 1 },
        type: { enum: ['recommendation_viewed', 'recommendation_clicked', 'funnel_step'] },
        targetType: { enum: ['destination', 'activity'] },
        targetId: { bsonType: 'string' },
        properties: { bsonType: 'object' },
        occurredAt: { bsonType: 'date' },
        receivedAt: { bsonType: 'date' },
      },
    },
  },
};

function ensureCollection(name, validator) {
  const options = { validator, validationLevel: 'strict', validationAction: 'error' };
  const exists = target.getCollectionNames().includes(name);
  if (exists) {
    target.runCommand({ collMod: name, ...options });
    print(`  ${name} : validateur mis à jour`);
  } else {
    target.createCollection(name, options);
    print(`  ${name} : collection créée`);
  }
}

function ensureIndex(coll, keys, options) {
  const name = target.getCollection(coll).createIndex(keys, options || {});
  print(`  ${coll} : index ${name}`);
}

function ensureTtl(coll, name, field, seconds) {
  try {
    target.getCollection(coll).createIndex({ [field]: 1 }, { name, expireAfterSeconds: seconds });
  } catch (e) {
    if (e.codeName !== 'IndexOptionsConflict') throw e;
    target.runCommand({ collMod: coll, index: { name, expireAfterSeconds: seconds } });
  }
  print(`  ${coll} : index TTL ${name} (${seconds} s)`);
}

print(`Initialisation de la base ${dbName}`);

for (const [name, validator] of Object.entries(VALIDATORS)) {
  ensureCollection(name, validator);
}

ensureIndex('conversations', { userId: 1, lastMessageAt: -1 });

ensureIndex('messages', { conversationId: 1, createdAt: -1, _id: -1 });
ensureIndex('messages', { userId: 1 });

ensureIndex('analytics_events', { type: 1, occurredAt: -1 });
ensureIndex('analytics_events', { userId: 1 });
ensureTtl('analytics_events', 'ttl_received_at', 'receivedAt', NINETY_DAYS);

// Pas de TTL sur messages ni conversations : la durée de conservation n'est pas encore
// fixée avec la personne chargée du RGPD (voir choix-odm-mongodb.md).

print('MongoDB prêt.');
