# Revue complète de l'app — juillet 2026

> **Statut (2026-07-12) : remédiation effectuée.** Le critique (C1) et les 8
> high (H1-H8) sont corrigés et couverts par des tests. Les mediums M1-M6 et
> M8-M12 sont corrigés ; **M7 (N+1 `fetchSummaries` pour une activité en
> cours) a été délibérément déprioritisé** — l'analyse a montré que son coût
> réel est borné à une ouverture de l'onglet Activités par visite (pas une
> boucle continue), impact bien moindre que l'estimation initiale ; à
> reprendre si un besoin concret se présente (nécessiterait de faire de
> `ActivityLocalDataSource` un singleton pour mémoïser, ou de brancher la
> liste sur l'état live du `MapBloc`).
>
> **Statut LOW (2026-08-03, passe 1.3) :** L-D1, L-D2, L-D3, L-D7 et
> L-G1 à L-G8, L-U2 sont corrigés et marqués ✅ ci-dessous (vérifiés dans le
> code, pas seulement déclarés). Restent ouverts : L-D4 à L-D6, L-D8 (dette
> de test), L-G6, et les items UI/accessibilité L-U1, L-U3 à L-U11 — backlog
> pour une prochaine session.
>
> Document destiné à guider un **agent correcteur dédié**, distinct de
> `AUDIT-2026-07.md` (qui portait spécifiquement sur le pipeline de
> localisation Android et le bug de kill de process). Celui-ci couvre
> l'ensemble de l'app : couche données/DB, présentation (blocs/UI), use
> cases/plateforme (Android/iOS), et le niveau projet (build, CI, doc,
> dépendances).
>
> Méthodologie : quatre revues indépendantes en parallèle, chacune
> vérifiant ses affirmations dans le code avant de les reporter (pas de
> lint automatique — lecture humaine simulée). Chaque observation cite
> `fichier:ligne`. Sévérités : **critical** (bloquant avant toute
> publication), **high** (bug réel affectant des utilisateurs réels),
> **medium** (dette ou bug à impact limité/rare), **low** (poli mais pas
> urgent). Les recoupements entre les 4 revues ont été fusionnés en une
> seule entrée.
>
> État au moment de l'audit : `design-refresh` branch, commit `040ce64`
> (juste après l'ajout de la fonctionnalité de détection de perte de
> signal GPS `signalLost` — voir `CHANGELOG.md`/`README.md`). Analyse
> statique propre (`flutter analyze` : 0 issue), 90 tests unitaires verts,
> smoke-test de lancement sur Pixel 5 (Android 14) sans crash.

---

## CRITICAL — bloquant avant toute publication F-Droid/release publique

### ✅ FIXED — C1. `applicationId`/`namespace`/bundle id toujours `com.example.furtive`
- **Fichiers** : `android/app/build.gradle.kts:15,31` (namespace + applicationId,
  avec le TODO du template Flutter encore présent ligne 30), package Kotlin
  `com.example.furtive`, `ios/Runner.xcodeproj/project.pbxproj:498`.
- **Pourquoi c'est critique** : F-Droid **rejette** les app IDs `com.example.*`
  à la soumission. L'ID est **irréversible** après publication : le changer
  plus tard casse les mises à jour et l'identité de signature pour tous les
  utilisateurs déjà installés (nouvelle app = perte des données locales, sauf
  export/réimport GPX manuel). Chaque release GitHub déjà publiée sous cet id
  aggrave le coût de la migration. `AUDIT-2026-07.md` §9 documente que la
  décision a été « différée intentionnellement » — c'est acté, mais c'est la
  dernière fenêtre où la base installée est petite.
- **Fix** : choisir un ID définitif (ex. `io.github.ethicnology.furtive` ou
  `org.ethicnology.furtive`), renommer namespace + package Kotlin +
  `MainActivity` + bundle id iOS, documenter la migration dans le CHANGELOG
  (export GPX → réinstall → import) pour les utilisateurs existants.

---

## HIGH

### ✅ FIXED — H1. Export GPX cassé sur iOS, fragile sur Android selon le dossier choisi
- **Fichier** : `lib/core/facades/file_system_facade.dart:14-25`.
- **iOS** : `getDirectoryPath()` n'est **pas implémenté** par
  `file_selector_ios` 0.5.3+2 (vérifié dans le package : seuls
  `openFile`/`openFiles` existent, la platform interface jette
  `UnimplementedError`). Chaque export GPX sur iOS échoue avec
  « Failed to save file: UnimplementedError… ». Fonctionnalité totalement
  morte sur une plateforme pourtant maintenue (Info.plist, AppDelegate,
  exclusions de backup en place).
- **Android** : `file_selector_android` 0.5.1+17 convertit l'URI SAF choisi
  en chemin brut (`FileUtils.java:61-97`) et jette `UnsupportedOperationException`
  pour tout volume non-`primary` (carte SD, USB) ou toute authority hors
  `com.android.externalstorage.documents`. Avec `targetSdk=36` (scoped
  storage), l'écriture via `dart:io` sur ce chemin n'est autorisée que dans
  les collections bien connues (`Download/`, `Documents/`) — un dossier
  arbitraire choisi par l'utilisateur échoue en `EPERM`. La permission SAF
  accordée n'est en réalité jamais exploitée.
- **Fix** : passer par la share sheet mobile (`share_plus`, déjà une
  dépendance du projet — `SharePlus.instance.share(ShareParams(files:
  [XFile(path)]))`) plutôt qu'un sélecteur de dossier ; réserver
  `getDirectoryPath` aux cibles desktop (linux/macos/windows) où il
  fonctionne réellement.

### ✅ FIXED — H2. Bug de tri qui casse la persistance des points `signalLost` (fonctionnalité tout juste ajoutée)
- **Fichiers** :
  `lib/core/usecases/score_activity_use_case.dart:39,44` (offsets ±1µs),
  `lib/core/usecases/import_activity_from_gpx_use_case.dart:116,126` (idem),
  `lib/core/database/tables/activity_points_table.dart:12` (colonne
  `dateTime()`, pas de `build.yaml` dans le repo),
  `lib/core/entities/activity_entity.dart:172` (`List.sort`).
- **Description** : sans `build.yaml`, Drift stocke les `DateTimeColumn` au
  format par défaut — **timestamp Unix en secondes**, millisecondes ET
  microsecondes tronquées à l'écriture. Les points-frontières
  `signalLost` (dupliqués à ±1µs du point encadrant le gap, pour former un
  segment dédié) retombent donc, après un rechargement depuis la DB, à
  **exactement la même seconde** que leur point ancre. `_segmentPoints`
  trie ensuite avec `List.sort`, qui n'est **pas stable** en Dart au-delà de
  ~32 éléments (vérifié empiriquement) — sur une activité de plusieurs
  milliers de points, un point-frontière peut se retrouver trié *avant* son
  jumeau actif.
- **Conséquence** : au rechargement (page détail, resume après kill,
  recalcul d'agrégats legacy), le segment `signalLost` se scinde en
  segments d'un seul point → `signalLostDuration` s'effondre à ~0, le rendu
  pointillé disparaît (une polyline à 1 point ne dessine rien), et un vrai
  tronçon actif peut sortir du segment actif → `activeDistanceMeters`
  recalculé diverge de l'agrégat stocké en DB. C'est précisément le bug que
  la fonctionnalité signalLost devait éviter — mais seulement en mémoire
  pendant l'enregistrement live, pas après relecture.
- **Fix** (deux volets) :
  1. Tri déterministe : faire remonter l'`id` de ligne (déjà l'ordre de
     lecture, `ORDER BY id ASC`) dans `ActivityPointModel`/
     `ActivityPointEntity` et trier par `(time, id)`, ou utiliser
     `mergeSort` (stable, `package:collection`) au lieu de `List.sort`.
  2. Persister à une précision qui préserve l'offset : colonne millisecondes
     (`build.yaml` + migration), et passer les offsets à ±1 ms au lieu de
     ±1 µs.
  3. Ajouter un test de round-trip DB (`store()`/`score()` puis
     `fetchSingle()`) sur une activité avec gap — aucun test actuel
     n'exerce ce chemin (tous travaillent sur des entités en mémoire, où la
     précision µs est intacte).

### ✅ FIXED — H3. Double ouverture concurrente du stream de positions GPS
- **Fichier** : `lib/features/map/bloc/map_bloc.dart:131-139` (`InitMap`),
  `192-215` (`_openPositionStream`), `220-258` (`EnsureTracking`).
- **Description** : le transformer par défaut de bloc 9.x traite les
  événements **concurremment** (vérifié dans la source de `bloc` 9.2.1).
  `_positionStream` n'est assigné qu'**après** l'`await` de
  `_startTrackPositionUsecase()` — le garde `isColdOpen = _positionStream
  == null` est un check-then-act traversé par un await. Scénario réaliste :
  `OnboardingPage._finish` fait `add(InitMap)` puis `pushReplacement` vers
  `MapPage`, dont `initState` refait `add(InitMap)` si le style n'est pas
  encore chargé — ce qui arrive quasi systématiquement puisque le premier
  handler est encore dans son await à ce moment. Les deux handlers voient
  `_positionStream == null` et appellent chacun `listen()`.
- **Conséquence** : le premier abonnement fuit définitivement (plus aucune
  référence, jamais annulable) et chaque fix GPS dispatch alors **deux**
  `UpdateUserLocation` → pendant un enregistrement, chaque fix est écrit
  deux fois en DB (timestamps identiques). Même race entre `onDone →
  InitMap` et `didChangeAppLifecycleState → EnsureTracking`, dont le
  cancel/reopen n'est pas non plus protégé.
- **Fix** : mémoïser le Future d'ouverture en vol (`Future<void>?
  _openingStream; Future<void> _ensureStreamOpen() => _openingStream ??=
  _openPositionStream().whenComplete(() => _openingStream = null);`), ou
  `transformer: droppable()` (package `bloc_concurrency`) sur `InitMap` et
  `EnsureTracking`.

### ✅ FIXED — H4. La carte entière rebuild à chaque tick du timer 1s (perf/batterie)
- **Fichiers** : `lib/features/map/pages/map_page.dart:212-449`,
  `lib/features/map/bloc/map_bloc.dart:536-547` (`UpdateElapsedTime`),
  `lib/core/entities/activity_entity.dart:120-155,393-530`.
- **Description** : le `BlocBuilder<MapBloc, MapState>` n'a **pas de
  `buildWhen`**. Chaque tick du timer (1×/s) et chaque fix GPS (2 emits/fix,
  ~5s) rebuild `FlutterMap` + `VectorTileLayer` +
  `activity.toPolylineLayer()` (remappe tous les points en `LatLng`) +
  `KmMilestonesLayer` (reparcourt tous les points avec
  `Geolocator.distanceBetween`) + `RichAttributionWidget` + tous les FABs.
  Seul `segments` est mémoïsé par Expando ; distance/durée/D+/milestones
  sont recalculés O(n) à chaque tick. Sur une sortie de 2-3h (milliers de
  points), c'est du jank et de la batterie brûlée chaque seconde, sur un
  écran qui reste allumé pendant tout l'enregistrement — le pire cas
  d'usage pour une régression de performance.
- **Fix** : (a) séparer l'overlay stats/FABs de la carte dans des
  `BlocSelector`/`BlocBuilder` distincts ; (b) `buildWhen` sur le builder
  carte ignorant les changements limités à `elapsedTime` ; (c) mémoïser
  polyline/milestones par identité d'instance d'activité (même mécanique
  Expando que `segments`).

### ✅ FIXED — H5. `KmSplitsChart` : plus rapide/plus lent inversés en mode Vitesse
- **Fichier** : `lib/core/widgets/km_splits_chart.dart:38-57` (vs.
  commentaire l.38-39 et `_value` l.122-123).
- **Description** : le code compare `v < bestVal → fastestIdx` / `v >
  worstVal → slowestIdx` sans jamais brancher sur le métrique actif
  (`_metric`). Correct en mode pace (min = rapide), **inversé en mode
  km/h** (min = plus lent) : le km le plus lent est coloré comme le plus
  rapide et vice-versa. Information factuellement fausse affichée à
  l'utilisateur.
- **Fix** : `final fasterIsSmaller = _metric == _Metric.pace;` et comparer
  en conséquence, ou normaliser un rang signé avant comparaison.

### ✅ FIXED — H6. Aucune CI sur push/PR
- **Fichier** : `.github/workflows/build-android.yml:3-4` (déclenchement
  `workflow_dispatch` uniquement).
- **Description** : aucun check automatique n'existe sur `push`/`pull_request` —
  ni `dart format --set-exit-if-changed`, ni `flutter analyze`, ni
  `flutter test` (90 tests jamais exécutés en CI), ni parité des fichiers
  `.arb` (`make translations`), ni `verify-reproducible`.
- **Fix** : ajouter un workflow léger `on: [push, pull_request]` (setup
  Flutter depuis `.fvmrc`, puis format + analyze + test + parité ARB), et un
  `verify-reproducible` en cron hebdomadaire.

### ✅ FIXED — H7. `versionCode` (build number) figé à 1 sur toutes les releases publiées
- **Fichier** : `pubspec.yaml:19` (`1.2.0+1`) ; vérifié dans l'historique
  git : `1.0.0+1` et `1.1.0+1` aussi.
- **Description** : F-Droid (et Android en général) exige un `versionCode`
  strictement croissant et unique par version publiée pour détecter les
  mises à jour. Le build number n'a jamais été incrémenté à travers 3
  releases.
- **Fix** : incrémenter à chaque release (ex. `1.3.0+4`), ou adopter un
  schéma dérivé de la version sémantique (ex. `10300`).

### ✅ FIXED (partiellement) — H8. Zéro test sur les blocs — dont le chemin qui a causé le bug P0 déjà corrigé
- **Fichier** : aucun test pour `MapBloc` (23,6K, le plus gros fichier de
  logique du projet), `PreferencesBloc`, `PermissionsBloc`, `ActivitiesBloc`.
- **Description** : `MapBloc._onInitMap` contient précisément le flux
  resume-après-kill dont le bug était le P0 de `AUDIT-2026-07.md` §1.2 (le
  correctif « resume avant le fix one-shot, garde `isColdOpen` ») —
  aucun test de régression ne verrouille ce comportement. Également sans
  test : `resume_ongoing_activity_use_case.dart`, `share_activity_use_case.dart`,
  `export_activity_to_gpx_use_case.dart`, aucun test de widget/page.
- **Fix priorisé** : (1) test de `MapBloc._onInitMap` avec use cases fakés
  (l'échec du fix one-shot ne doit pas empêcher le resume) — le scénario
  qui a réellement affecté des utilisateurs ; (2) test de round-trip
  export→import GPX au niveau use case.

---

## MEDIUM

### ✅ FIXED — M1. Course sur le bracketing de gap GPS + perte de point sur la polyline live
- **Fichier** : `lib/features/map/bloc/map_bloc.dart:389-456`
  (`_onScoreActivity`).
- **Description** : le transformer par défaut traite les `ScoreActivity`
  concurremment. `previous = activity.points.last` (pour la détection de
  gap) est capturé **avant** l'await — deux handlers en vol simultané (ex.
  après un resume, l'OS livrant un backlog de fixes bufferisés) peuvent
  tous deux calculer un gap sur le même `previous` et écrire **deux**
  paires de points `signalLost` en DB. Par ailleurs, même sans gap, deux
  handlers concurrents peuvent perdre un point de la polyline en mémoire
  (l'un écrase l'état de l'autre à l'emit) — la DB reste correcte, seul
  l'état en mémoire se désynchronise jusqu'au prochain resume.
- **Fix** : `on<ScoreActivity>(_onScoreActivity, transformer: sequential())`
  (package `bloc_concurrency`) — à la cadence ~5s des fixes, la
  sérialisation est sans coût perceptible.

### ✅ FIXED — M2. Import GPX : parsing DOM de fichiers jusqu'à 50 MB sur l'isolate UI
- **Fichier** : `lib/core/usecases/import_activity_from_gpx_use_case.dart:36,45,49`.
- **Description** : `readAsString()` + `XmlDocument.parse()` s'exécutent
  sur l'isolate principal. Un GPX de 50 MB (le plafond actuel) produit un
  DOM de plusieurs centaines de MB (risque d'OOM sur appareil modeste) et
  fige l'UI plusieurs secondes. Le pattern `compute()` existe déjà ailleurs
  dans le projet (décodage du style de carte).
- **Fix** : abaisser le plafond à ~10-20 MB et déporter parse + conversion
  en points dans un isolate (`compute`/`Isolate.run`), le use case ne
  gardant que l'écriture DB sur l'isolate principal.

### ✅ FIXED — M3. Update check GitHub actif par défaut — anti-feature pour F-Droid
- **Fichiers** :
  `lib/features/permissions/presentation/pages/check_permission_page.dart:43`,
  `lib/core/entities/preferences_entity.dart` (`checkUpdates = true` par
  défaut).
- **Description** : à chaque démarrage (cache 24h), l'app contacte
  `api.github.com` par défaut, révélant l'installation à GitHub/Microsoft
  (IP + User-Agent). Implémentation propre par ailleurs (opt-out réel sans
  appel réseau, timeout 5s, validation du payload), mais un phone-home
  opt-out par défaut est typiquement étiqueté anti-feature par F-Droid, qui
  gère lui-même les mises à jour.
- **Fix** : passer en opt-in à l'onboarding, ou désactiver par flavor/
  `--dart-define` sur le build destiné à F-Droid. Nit associé : dans
  `check_version_service.dart`, `_lastCheck` est positionné **avant** la
  requête réseau — un échec transitoire au premier lancement supprime
  toute nouvelle tentative pour la session ; ne le stamper qu'après succès.

### ✅ FIXED — M4. Le snackbar « nouvelle version disponible » n'est quasiment jamais montré
- **Fichiers** :
  `lib/features/permissions/presentation/pages/check_permission_page.dart:43`,
  `lib/core/check_version_service.dart:67-91`.
- **Description** : `checkNewVersion(context)` reçoit le `context` de
  `CheckPermissionPage`, démonté par un `pushReplacement` bien avant la fin
  du HTTP (jusqu'à 5s de timeout). Le garde `if (!context.mounted) return;`
  fait tomber silencieusement le résultat sur la plupart des lancements.
- **Fix** : `GlobalKey<ScaffoldMessengerState>` sur le `MaterialApp`
  (`main.dart`), utilisé par le service au lieu du `context` de la page
  éphémère.

### ✅ FIXED — M5. `PreferencesBloc` : erreurs avalées + effets de bord potentiellement sautés après fermeture
- **Fichiers** : `lib/features/preferences/bloc/preferences_bloc.dart:94-129`,
  `lib/features/preferences/page.dart:89-92`.
- **Description** : (a) aucun try/catch autour de
  `_updatePreferencesUseCase` — une exception part dans le handler
  d'erreur global du bloc alors que la page a déjà `pop()`, l'utilisateur
  croit ses réglages sauvés sans l'être. (b) le garde `if (isClosed)
  return;` est placé **avant** les effets de bord (`setLocale`, `InitMap`,
  `setShowWhenLocked`) qui n'appellent pas `emit` — si l'écriture DB
  dépasse la durée de l'animation de pop, les réglages sont persistés mais
  jamais appliqués tant que l'app n'est pas redémarrée.
- **Fix** : try/catch avec log + feedback utilisateur (mécanisme global,
  cf M4) ; déplacer le garde `isClosed` pour qu'il ne protège que l'`emit`,
  pas les effets de bord.

### ✅ FIXED — M6. Suite « pile traces OSM » — code mort + données tierces jamais purgées
- **Fichiers** : `lib/core/repositories/trace_repository.dart:30-35`
  (`store` sans appelant), `lib/core/datasources/trace_local_data_source.dart`
  (fetch et store inutilisés), `trace_metadata_table.dart`,
  `trace_points_table.dart`, `get_traces_use_case.dart`, bouton `FetchTraces`
  commenté dans `map_page.dart`.
- **Description** : la persistance des traces OSM tierces a été retirée du
  design (documenté dans `GetTracesUseCase` comme contradictoire avec la
  posture privacy), mais le code d'écriture/lecture est resté et surtout
  **aucune migration ne purge les lignes déjà accumulées** par les
  anciennes versions installées — les traces GPS tierces re-insérées « à
  chaque pan » restent sur le disque des utilisateurs qui upgradent, pour
  toujours.
- **Fix** : migration DB (v8) purgeant `trace_points`/`trace_metadatas` (ou
  drop des tables), suppression de `TraceLocalDataSource`,
  `TraceRepository.store`, `TraceModel.fromEntity`.

### ⏸️ DÉPRIORITISÉ (non fait) — M7. `fetchSummaries` : rechargement complet des points d'une activité en cours à chaque ouverture de la liste
- **Fichier** : `lib/core/datasources/activity_local_data_source.dart:274-298`.
- **Description** : la sentinelle `-1` (jamais persistée pour une activité
  en cours, par design) force un recalcul complet à chaque ouverture de la
  liste : tous les points sont rechargés (jusqu'à ~17k lignes sur 24h
  d'après le commentaire du schéma) puis la segmentation/distance est
  recalculée côté Dart.
- **Fix** : pour la ligne en cours, utiliser un agrégat SQL approché
  (COUNT/min-max time) ou réutiliser l'état déjà vivant du `MapBloc` (liste
  et carte coexistent dans la même app) ; à défaut, mémoïser sur
  `(activityId, dernier id de point)`.

### ✅ FIXED — M8. `fetchOngoing`/`cease()` : réconciliation non transactionnelle, throw non idempotent
- **Fichier** : `lib/core/datasources/activity_local_data_source.dart:211-244`,
  `cease()` lignes 168-170.
- **Description** : entre le `SELECT` des orphelins et chaque
  `cease(orphan.id)`, rien n'est atomique. `cease()` jette
  `AppError('Activity already stopped')` si la ligne a déjà été clôturée
  entre-temps — l'exception remonte jusqu'à `fetchOngoing`, faisant
  échouer l'init du `MapBloc` et perdant la reprise d'un run qui allait
  bien.
- **Fix** : pour les chemins d'auto-cease, remplacer le throw par un no-op
  conditionnel (`UPDATE ... WHERE stopped_at IS NULL`, ignorer un rowcount
  de 0), ou envelopper toute la réconciliation dans une transaction.

### ✅ FIXED — M9. Auto-cease d'une activité abandonnée : `stoppedAt` = maintenant au lieu du dernier fix
- **Fichier** : `lib/core/datasources/activity_local_data_source.dart:183`
  (via `fetchOngoing`).
- **Description** : une activité orpheline abandonnée depuis plusieurs
  jours reçoit un `stoppedAt` au moment de l'auto-cease, pas au moment du
  dernier point réel. Les agrégats (calculés depuis les points) restent
  corrects, mais toute métadonnée basée sur `stoppedAt` (durée écoulée,
  tri, futur export) devient mensongère.
- **Fix** : paramètre optionnel `DateTime? stoppedAt` sur `cease()`,
  alimenté par le timestamp du dernier fix dans les chemins d'auto-cease.

### ✅ FIXED — M10. `Uri.replace` casse potentiellement les templates de tuiles `{z}/{x}/{y}`
- **Fichier** : `lib/core/datasources/map_remote_data_source.dart:190,233-244`
  (`_withKey`).
- **Description** : `Uri.parse(template).replace(queryParameters: {...})`
  percent-encode les accolades littérales du template (`{z}` →
  `%7Bz%7D`), que `NetworkVectorTileProvider` (vector_map_tiles) substitue
  ensuite via une regex qui ne matche pas la forme encodée. Actuellement
  masqué car le TileJSON Protomaps renvoie déjà des templates avec
  `?key=` inclus (early-return avant `_withKey`) — un changement côté
  Protomaps déclencherait un 404 sur toutes les tuiles pour tous les
  builds avec clé.
- **Fix** : concaténation textuelle (`url + (contains('?') ? '&' : '?') +
  'key=$key'`) plutôt que passer par `Uri.replace` sur un template.

### ✅ FIXED — M11. Toast « activité démarrée » affiché même en cas d'échec de démarrage
- **Fichiers** : `lib/features/map/pages/map_page.dart:138-164`,
  `lib/features/map/bloc/map_bloc.dart:381-386`.
- **Description** : le `listenWhen` du toast de succès matche sur la
  transition `loadingStatus: startingActivity → null`, qui se produit
  aussi dans le chemin d'erreur (`finally` émettant `loadingStatus: null`
  après un `catch`). Un échec de démarrage affiche donc un gros toast de
  succès en même temps que le snackbar d'erreur.
- **Fix** : ajouter `&& current.activity != null` au `listenWhen`.

### ✅ FIXED — M12. `ActivitiesListPage` : spinner infini si le premier fetch échoue
- **Fichier** : `lib/features/activities/pages/activities_list_page.dart:112-114`.
- **Description** : sur erreur, `activities` reste `null` et `isLoading`
  passe à `false` → la condition `isLoading || activities == null` affiche
  un spinner permanent (seul un snackbar de 3s signale l'erreur, sans
  action de retry).
- **Fix** : brancher sur `state.error != null && activities == null` pour
  afficher une vue d'erreur avec bouton réessayer.

---

## LOW

Regroupées par thème ; chacune reste factuelle et vérifiée mais à impact
limité ou rare.

### Données / DB
- **L-D1.** ✅ FIXED (1.3) — `mapLanguage` supprimée (schéma v9) et
  `accuracyInMeters` (schéma v12) ; plus aucune colonne morte ne traverse
  les couches.
- **L-D2.** ✅ FIXED (1.3) — `updateName` est désormais un `UPDATE` unique
  avec vérification du rowcount (`AppError` si 0 ligne), atomique et sans
  `SELECT` redondant.
- **L-D3.** ✅ FIXED (1.3) — un fix hors-ordre est rejeté
  (`GpsRejectionReason.outOfOrder`) **sans** déplacer `_lastAccepted`.
- **L-D4.** Mélange UTC/local des `DateTime` selon la provenance (écriture
  UTC explicite, lecture Drift en heure locale par défaut) — pas de bug
  d'instant aujourd'hui mais fragile pour tout code futur inspectant
  `.hour`/`.isUtc`. Normaliser dans `ActivityPointModel.fromDatabase`.
- **L-D5.** API modèle↔entité en méthodes statiques (`Model.toEntity(m)`)
  plutôt qu'en méthodes d'instance — dette de verbosité, chaque nouveau
  champ se recopie à 6 endroits.
- **L-D6.** `TraceRemoteDataSource._getCapped` discrimine une exception par
  `toString().contains(...)` — fragile, préférer un type dédié.
- **L-D7.** ✅ FIXED (1.3) — `fetchSummaries` trie par `started_at DESC,
  id DESC` : les ex æquo (double import du même GPX) ont un ordre stable,
  la pagination ne peut plus sauter ni répéter une ligne.
- **L-D8.** Dette de test DB : migration testée seulement depuis
  `from=2` (jamais `from=1`), round-trip incomplet de `mapTilesEnabled`/
  `showOnLockScreen`, chemins non couverts (`updateName`/`delete` sur id
  inconnu, re-seed préférences si ligne manquante, persistance backfill
  `fetchSummaries` sur une ligne legacy avec `stoppedAt` non-null).

### GPX / export-import
- **L-G1.** ✅ FIXED (1.3) — export via `_decimal()`/`toStringAsFixed`
  (7 décimales lat/lon, 2 pour ele) ; plus de notation scientifique.
- **L-G2.** ✅ FIXED (1.3) — `_escapeXml` supprime les caractères de
  contrôle C0 en plus d'échapper les entités prédéfinies.
- **L-G3.** ✅ FIXED (1.3) — `FileSaveCancelled` distingue l'annulation
  d'un échec réel ; les appelants la traitent comme un no-op silencieux.
- **L-G4.** ✅ FIXED (1.3) — `startedAt`/`stoppedAt` importés = min/max
  sur les temps des fixes actifs, pas first/last du document.
- **L-G5.** ✅ FIXED (1.3) — un `<time>` sans fuseau est interprété en
  UTC, conformément à la spec GPX.
- **L-G6.** Deux formes de fichiers GPX silencieusement mal gérées :
  `<trkpt>` orphelins hors `<trkseg>` ignorés si un autre `<trk>` du
  fichier a des segments ; espaces de noms préfixés (`<x:trkpt>`) donnant
  un faux `GpxNoPointsError` — `lib/core/utils/gpx.dart:52-73`.
- **L-G7.** ✅ FIXED (1.3) — nom de fichier d'export tronqué à 100
  caractères après passage en liste blanche.
- **L-G8.** ✅ FIXED (1.3) — commentaire XXE/billion-laughs retiré ; le
  plafond de 10 MB est désormais justifié (mémoire pic) et épinglé par
  des tests.
  commentaire ne s'applique pas tel quel (le plafond de taille reste une
  bonne défense en profondeur, juste corriger le commentaire).

### Présentation / UI / accessibilité
- **L-U1.** `_mapController.camera` accédé sur un contrôleur potentiellement
  non attaché si la carte se démonte pendant un listener actif
  (`map_page.dart:196-209,226-245`).
- **L-U2.** ✅ FIXED (1.3) — le commentaire obsolète a disparu avec la
  réorganisation MapBloc/RecordingBloc/PositionStreamController.
- **L-U3.** FAB à largeur fixe 115px risquant l'overflow avec des libellés
  localisés longs (el/de/ar vérifiés) — `map_page.dart:42,351-352`.
- **L-U4.** `PermissionsState.errorMessage`/`PreferencesState.error` émis
  mais jamais lus par aucune page, jamais purgés.
- **L-U5.** `LabeledDropdown.initialValue` ne se resynchronise pas après le
  premier build (sémantique `DropdownButtonFormField` post-dépréciation) —
  latent tant que rien ne reset les prefs en externe.
- **L-U6.** Double-tap dans la liste d'activités empile des pushes
  dupliqués (`activities_list_page.dart:186,199-212`) — pas de garde.
- **L-U7.** Accessibilité : IconButtons renommer/supprimer/exporter sans
  `tooltip` ; le bouton « maintenir 3s pour arrêter » n'a aucune
  sémantique `Semantics(button:true)` et est probablement inutilisable
  avec TalkBack ; le chrono live sans contrôle de live region.
- **L-U8.** Strings non localisées : préfixe `"version "` en dur, `"$_logsSizeKb
  kB"`, unités concaténées en dur (`' km'`, `' km/h'`, `' m'`, `' /km'`)
  dans plusieurs widgets.
- **L-U9.** Copie de ligne de log par long-press probablement morte : le
  `GestureDetector` autour d'un `SelectableText` perd l'arène de gestes au
  profit de la sélection de texte (`logs_page.dart:290-315`).
- **L-U10.** Écriture DB après cease : un score en vol pendant un cease
  peut écrire un point avec `time > stoppedAt` (impact cosmétique
  seulement, la page détail borne déjà sur `stoppedAt`).
- **L-U11.** `ScaffoldMessenger.of(context)` appelé après `Navigator.pop`
  sur le context de la page qui vient d'être retirée
  (`activity_detail_page.dart:439-444`) — fonctionne aujourd'hui mais
  fragile ; capturer le messenger avant le pop.
- **L-U12.** Commentaire trompeur sur `ModalRoute.isCurrent` qui ne protège
  pas contre le cas décrit (les 3 onglets partagent la même route) —
  impact réel négligeable, corriger le commentaire.
- **L-U13.** `_onPauseActivity` (chemin resume) ne fait pas de
  `_elapsedTimer?.cancel()` défensif avant de recréer le timer, contrairement
  aux autres chemins similaires.

### Use cases / plateforme
- **L-P1.** `Global.init()`/`initializeDateFormatting()` non gardés avant
  `runApp` — un échec de channel plateforme bloque l'app sur le splash de
  façon irrécupérable (`lib/main.dart:29-31`).
- **L-P2.** `_onEnsureTracking` ne répare le stream que si une activité est
  en cours — hors enregistrement, le marqueur "ma position" peut rester
  figé après une suspension OS silencieuse du stream.
- **L-P3.** Nommage de fichiers use case périmé : `GetMapConfigUseCase`
  vit dans `get_map_tile_url_use_case.dart`, `GetActivityUseCase` dans
  `get_activities_use_case.dart`.

### Niveau projet / build / doc
- **L-J1.** `cupertino_icons` dépendance inutilisée (aucune occurrence de
  `CupertinoIcons` dans `lib/`).
- **L-J2.** `.env.example` suggère un workflow dotenv qui n'existe pas
  (aucun package dotenv, tout passe par `--dart-define`/env vars) —
  remplacer par une note README.
- **L-J3.** `android/gradle/wrapper/gradle-wrapper.properties` sans
  `distributionSha256Sum` — seul maillon de la chaîne "reproductible"
  téléchargé sans vérification d'intégrité.
- **L-J4.** `android.buildToolsVersion` (gradle.properties) non câblé dans
  `build.gradle.kts` — AGP peut choisir/télécharger sa propre version,
  contredisant l'intention "single source of truth".
- **L-J5.** `isMinifyEnabled = false`/`isShrinkResources = false` en
  release sans rationale écrite (le choix reproductibilité est plausible
  mais non documenté, contrairement au signing).
- **L-J6.** `android.enableJetifier=true` et `multiDexEnabled = true`
  probablement superflus (minSdk 24, dépendances modernes) — ralentissent
  le build sans bénéfice apparent.
- **L-J7.** `Containerfile.tools` : script d'installation FVM non
  versionné (`curl | bash`), zip cmdline-tools sans checksum — surface
  supply-chain non mentionnée dans le README (l'image *tools* n'a pas
  besoin d'être hermétique puisque c'est l'APK qui doit l'être, mais à
  noter).
- **L-J8.** Check de parité ARB : one-liner Python illisible inliné dans
  le `makefile` — à extraire en script réutilisable par la CI (cf. H6).
- **L-J9.** Tag git `1.2.0` absent du dépôt local alors que
  `CHANGELOG.md` le référence — à vérifier/créer côté mainteneur.
- **L-J10.** `CHANGELOG.md` sans entrées pour `1.0.0`/`1.1.0` malgré l'en-tête
  "All notable changes".
- **L-J11.** Commentaire `pubspec.yaml` mentionnant `flutter_gen/gen_l10n`
  périmé (le code importe `package:furtive/l10n/app_localizations.dart`).
- **L-J12.** `vector_map_tiles: ^9.0.0-beta.8` — pré-release beta au cœur
  du rendu carte en production ; surveiller la 9.0.0 stable.
- **L-J13.** `DESIGN-AUDIT-MODEL-NOTES.md` — notes internes (choix de
  modèle IA, tarification) sans rapport avec le produit, n'a rien à faire
  dans un repo FOSS public destiné à F-Droid ; à supprimer ou déplacer.
- **L-J14.** Actions GitHub référencées par tag et non par SHA
  (`build-android.yml`) — incohérent avec la philosophie reproductibilité
  du projet.
- **L-J15.** `test/flutter_test_config.dart` charge une police pour des
  tests golden qui n'existent pas dans le repo — soit committer des
  goldens de non-régression, soit documenter l'attente.
- **L-J16.** README §Reproductible mentionnait Flutter `3.41.9` alors que
  `.fvmrc` est à `3.44.2` (probablement déjà corrigé dans une session
  antérieure — **à revérifier**, car `.fvmrc` a été bumpé au commit
  `ed46556` sans mise à jour du README à l'époque du premier passage
  d'audit outillé).

---

## Points vérifiés sains (pour éviter les faux positifs à une prochaine revue)

- Transactions DB (`store`, `score`, `cease`, `delete`) correctement
  atomiques ; garde anti score-après-cease réel et testé.
- `PRAGMA foreign_keys = ON` correctement activé + testé.
- Sentinelle `-1` cohérente entre migration v4, `store()`, `cease()`,
  `fetchSummaries`.
- Index DB suffisants pour les requêtes actuelles.
- Choix de ne pas faire de migration DDL pour l'enum `signalLost` (textEnum
  sans CHECK constraint) : valide.
- La logique de détection de gap dans `MapBloc` (uniquement entre deux
  fixes actifs, reset au `StartActivity`, fenêtre non polluée par le gap
  lui-même) est correcte — seul son point de défaillance est la
  persistance (H2 ci-dessus).
- Aucune coordonnée GPS dans les logs (grep exhaustif) ; clé Protomaps
  expurgée des logs ; nom d'appareil iOS délibérément exclu.
- Injection XML à l'export : `&<>"'` échappés, noms de fichiers whitelistés
  contre la traversée de chemin.
- Réseau : 3 destinations seulement (Protomaps opt-out, OSM inatteignable
  car code mort, GitHub opt-out), timeouts + caps de taille partout, clé
  API jamais envoyée hors host allowlisté, `usesCleartextTraffic="false"`.
- Pipeline GPS : NaN filtrés de façon redondante et cohérente à toutes les
  couches ; timestamps plateforme (pas `now()`) avec garde epoch-0 ;
  `getCurrentPosition` borné à 12s.
- `copyWith(x: null)` fonctionne correctement partout (dart_mappable,
  sentinelle `$none` vérifiée) — pas de piège malgré les apparences.
- Cycles de vie widgets : subscriptions/timers/controllers/observers
  correctement annulés/disposés à travers tout `lib/features/`.
- l10n : parité parfaite des 124 clés à travers les 26 locales (vérifiée
  par exécution du script de check).
- Signing : correctement hors repo des deux côtés (Android/iOS), aucun
  keystore commité.
- Manifest Android : exceptionnellement bien justifié (chaque permission
  commentée).

---

## Priorités suggérées pour l'agent correcteur

1. **C1** (applicationId) — à trancher avant toute nouvelle release, coût
   croissant avec le temps.
2. **H2** (persistance signalLost) — corrige une régression fraîchement
   introduite avant qu'elle n'atteigne des utilisateurs réels.
3. **H1** (export GPX cassé/fragile) — la seule porte de sortie des
   données utilisateur, actuellement non fiable sur les deux plateformes
   cibles.
4. **H3/H4** (race stream GPS, perf carte) — impact direct sur la fiabilité
   et la batterie du cas d'usage central (enregistrement long).
5. **H6/H7/H8** (CI, versionCode, tests blocs) — dette structurelle qui
   rend toute correction suivante plus risquée.
6. **H5** (splits inversés) — fix trivial, bug utilisateur visible.
7. Le reste des **medium** par ordre d'apparition, puis les **low** en
   fonction du temps disponible.
