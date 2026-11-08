# Google Mobile Ads uses WorkManager, whose Room database is created by reflection.
# Without these rules R8 strips the generated constructors and the release app crashes at launch
# ("Failed to create an instance of androidx.work.impl.WorkDatabase").
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class androidx.work.** { *; }
