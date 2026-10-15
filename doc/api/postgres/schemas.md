# API PostgreSQL — corps des requêtes/réponses

Complète `endpoints.md` (même dossier) avec ce qu'on envoie et ce qu'on reçoit. Mêmes
sections, même ordre.

**Convention** : `champ?` = optionnel. Types indicatifs (`string`, `number`, `boolean`,
`date` = ISO 8601, `enum(a|b|c)`). Les réponses de liste sont enveloppées dans un objet
nommé (`{ trips: [...] }`), jamais un tableau nu.

---

## Authentification

**POST /auth/register**
```
→ { email: string, password: string }
← 201 { id: string, email: string, createdAt: date }
```

**POST /auth/login**
```
→ { email: string, password: string }
← 200 { accessToken: string, refreshToken: string, expiresIn: number }
```

**POST /auth/refresh**
```
→ { refreshToken: string }
← 200 { accessToken: string, refreshToken: string, expiresIn: number }
```

**POST /auth/logout**
```
→ (rien — session identifiée par le token)
← 204
```

## Compte & profil voyageur

**GET /users/me**
```
← 200 { id: string, email: string, phone: string?, status: enum(active|suspended|deleted), createdAt: date }
```

**PATCH /users/me**
```
→ { email?: string, phone?: string }
← 200 <même forme que GET /users/me>
```

**DELETE /users/me**
```
← 204
```

**GET /users/me/questionnaire**
```
← 200 { questions: [{ id: string, code: string, label: string, axis: string, position: number }] }
```

**POST /users/me/questionnaire**
```
→ { answers: [{ questionId: string, value: number }] }
← 200 <même forme que GET /users/me/type> — recalculé après soumission
```

**GET /users/me/type**
```
← 200 {
    dominantType: enum(explorateur|epicurien|sociable|connecteur),
    scores: { urbanite, intensite, planification, social, confort, decouverte }: number,
    computedAt: date
  }
```

**GET /users/me/settings**
```
← 200 {
    notificationsEnabled: boolean, geolocationEnabled: boolean,
    communityVisible: boolean, privacyLevel: enum(standard|strict),
    offlineModeEnabled: boolean
  }
```

**PATCH /users/me/settings**
```
→ <sous-ensemble partiel de GET /users/me/settings>
← 200 <même forme que GET /users/me/settings>
```

## Notifications (Bonus)

**GET /notifications**
```
← 200 { notifications: [{ id: string, type: string, message: string, read: boolean, createdAt: date }] }
```

**PATCH /notifications/:id/read**
```
← 200 { id: string, read: true }
```

## Catalogue

**GET /destinations**  `?city=&country=&search=`
```
← 200 { destinations: [{ id: string, name: string, cityId: string, coverImageUrl: string?, popularityScore: number }] }
```

**GET /destinations/:id**
```
← 200 { id, name, description, coverImageUrl, city: { id, name, countryId } }
```

**GET /destinations/:id/activities**  `?category=&recommended=`
```
← 200 { activities: [{ id: string, name: string, category: string, priceRange: string?, recommendedProfiles: string[] }] }
```

**GET /activities/:id**
```
← 200 {
    id, name, description, address, priceRange: string?,
    openingHours: object?, contactPhone: string?, contactWebsite: string?, bookingUrl: string?,
    media: [{ url: string, origin: enum(official|community) }],
    averageRating: number?
  }
```

## Génération d'itinéraire

**POST /trips/generate**
```
→ {
    originCityId: string, destinationCityId: string,
    startDate: date, endDate: date,
    budget?: number, transportMode?: string,
    travelersUserIds?: string[]        // collaboration à plusieurs
  }
← 201 {
    proposalId: string,                // référence Redis, pas encore un trip persisté
    days: [{ dayIndex: number, date: date, steps: [
      { sequence: number, type: enum(activity|transport|accommodation|meal),
        activityId: string?, startTime: date?, endTime: date? }
    ]}]
  }
```

**POST /trips/generate/:proposalId/regenerate**
```
→ { feedback?: string }              // raison du rejet, optionnel, améliore la re-génération
← 200 <même forme que POST /trips/generate>
```

**POST /trips/generate/:proposalId/confirm**
```
→ (rien)
← 201 { trip: <même forme que GET /trips/:id> }
```

## Itinéraires

**GET /trips**  `?status=`
```
← 200 { trips: [{ id: string, title: string?, status: enum(draft|generated|active|completed|archived), startDate: date, endDate: date }] }
```

**GET /trips/:id**
```
← 200 {
    id, title, status, startDate, endDate, budget: number?, transportMode: string?,
    days: [{ dayIndex, date, steps: [{ id, sequence, type, activityId, startTime, endTime, status, notes }] }],
    transport: [{ leg: enum(outbound|return|intra), mode, departsAt, arrivesAt }],
    bookings: [{ id, category, status, referenceCode }]
  }
```

**PATCH /trips/:id**
```
→ { title?: string, startDate?: date, endDate?: date, budget?: number }
← 200 <même forme que GET /trips/:id>
```

**DELETE /trips/:id**
```
← 204
```

**PATCH /trips/:id/steps/:stepId**
```
→ { activityId?: string, startTime?: date, endTime?: date, status?: enum(planned|confirmed|modified|skipped) }
← 200 { id, sequence, type, activityId, startTime, endTime, status, notes }
```

**DELETE /trips/:id/steps/:stepId**
```
← 204
```

**POST /trips/:id/bookings**
```
→ { category: enum(flight|train|accommodation|activity), provider?: string, referenceCode?: string, bookingUrl?: string, reminderAt?: date }
← 201 { id, category, provider, referenceCode, status: "pending" }
```

## Historique & carnet

**GET /trips/history**
```
← 200 { trips: [<même forme que GET /trips>] }
```

**GET /trips/:id/journal**
```
← 200 { entries: [{ id: string, dayIndex: number?, stepId: string?, text: string?, summaryWord: string?, photos: string[] }] }
```

**POST /trips/:id/journal**
```
→ { stepId?: string, dayIndex?: number, text?: string, summaryWord?: string, photoUrls?: string[] }
← 201 <une entrée, même forme que ci-dessus>
```

**GET /trips/:id/journal/export**
```
← 200 { pdfUrl: string }   // génération asynchrone (Queue) ; url disponible une fois le job terminé
```

## Favoris

**GET /favorites**
```
← 200 { favorites: [{ id: string, targetType: enum(destination|activity|city), targetId: string, status: enum(favorite|considered), createdAt: date }] }
```

**POST /favorites**
```
→ { targetType: enum(destination|activity|city), targetId: string, status?: enum(favorite|considered) }
← 201 <un favori, même forme que ci-dessus>
```

**DELETE /favorites/:id**
```
← 204
```

## Avis

**GET /activities/:id/reviews**
```
← 200 { reviews: [{ id: string, userId: string, rating: number, comment: string?, createdAt: date }], averageRating: number }
```

**POST /activities/:id/reviews**
```
→ { rating: number, comment?: string }
← 201 <un avis, même forme que ci-dessus>
```

**DELETE /reviews/:id**
```
← 204
```
