# Enum helpers used by serialization and settings must survive shrinking.
-keepclassmembers enum com.mundymorning.collage.engine.** {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
