redis-core (aucune éviction, persistant)
-Session (Identity : révocation JWT)
-Queue (BullMQ : notifications, export du carnet, purge RGPD, relance du calcul de profil)
-Propositions, tâches de génération et clés d'idempotence (Assistant)

redis-cache (éviction autorisée)
-Cache (fiches destination/activité, classements, générations)
-Rate_limit (Bonus)