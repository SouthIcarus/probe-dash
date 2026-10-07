# R8 keep rules for release builds.

# WorkManager (pulled in by google_mobile_ads) builds its Room database by
# looking up the generated WorkDatabase_Impl class by name at app start.
# R8 full mode stripped its constructor, so build 3 crashed on launch with
# "Failed to create an instance of androidx.work.impl.WorkDatabase"
# (changelog #0007). Keep every Room database and its no-arg constructor.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
