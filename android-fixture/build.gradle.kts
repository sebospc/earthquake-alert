plugins {
    id("com.android.application")
}

android {
    namespace = "com.earthquakes.fixture"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.earthquakes.fixture"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
