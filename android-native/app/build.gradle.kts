plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

val leafwake = providers.gradleProperty("leafwake").map { it.toBooleanStrict() }.getOrElse(false)
val ownerKeystore = System.getenv("ABS_ANDROID_KEYSTORE")
val leafwakeSourceUrl = providers.gradleProperty("leafwakeSourceUrl").getOrElse("https://github.com/r4iju/audiobookshelf-app/tree/fork/native-tv")
gradle.taskGraph.whenReady {
    if (leafwake && allTasks.any { it.name in setOf("packageRelease", "signReleaseBundle", "bundleRelease", "assembleRelease") }) {
        require(!ownerKeystore.isNullOrBlank() && listOf("ABS_ANDROID_KEYSTORE_PASSWORD", "ABS_ANDROID_KEY_ALIAS", "ABS_ANDROID_KEY_PASSWORD").all { !System.getenv(it).isNullOrBlank() }) {
            "Leafwake release tasks require an owner signing key; debug-key fallback is forbidden."
        }
        require(Regex("https://github\\.com/r4iju/audiobookshelf-app/tree/[0-9a-f]{40}").matches(leafwakeSourceUrl)) {
            "Leafwake releases require leafwakeSourceUrl pointing to the exact 40-character source commit."
        }
    }
}

android {
    namespace = "com.audiobookshelf.android"
    compileSdk = 36

    defaultConfig {
        // Distinct preview identity: installs beside the working legacy app without touching its data.
        applicationId = if (leafwake) "com.forkzed.leafwake" else "com.audiobookshelf.app.nativepreview"
        minSdk = 24
        targetSdk = 36
        versionCode = if (leafwake) 1 else 200
        versionName = if (leafwake) "1.0.0-beta.1" else "0.15.0-native-preview"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        val scheme = if (leafwake) "leafwake" else "audiobookshelf-native-preview"
        manifestPlaceholders["oauthScheme"] = scheme
        manifestPlaceholders["displayName"] = if (leafwake) "Leafwake" else "@string/app_name"
        manifestPlaceholders["launcherIcon"] = if (leafwake) "@drawable/leafwake_icon" else "@mipmap/ic_launcher"
        buildConfigField("String", "OAUTH_REDIRECT", "\"$scheme://oauth\"")
        buildConfigField("boolean", "PUBLIC_RELEASE", leafwake.toString())
        buildConfigField("boolean", "CAST_ENABLED", (!leafwake).toString())
        buildConfigField("String", "SOURCE_URL", "\"${leafwakeSourceUrl}\"")
        resValue("string", "product_name", if (leafwake) "Leafwake" else "Audiobookshelf")
    }

    if (ownerKeystore != null) signingConfigs.create("owner") {
        storeFile = file(ownerKeystore)
        storePassword = System.getenv("ABS_ANDROID_KEYSTORE_PASSWORD")
        keyAlias = System.getenv("ABS_ANDROID_KEY_ALIAS")
        keyPassword = System.getenv("ABS_ANDROID_KEY_PASSWORD")
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
        }
        release {
            isMinifyEnabled = false
            // Internal distribution only: signed locally with the existing debug keystore unless
            // ABS_ANDROID_KEYSTORE points at an owner-provided keystore.
            signingConfig = if (ownerKeystore != null) signingConfigs.getByName("owner")
                else if (leafwake) null else signingConfigs.getByName("debug")
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
        resValues = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        resources.excludes += setOf("/META-INF/{AL2.0,LGPL2.1}", "META-INF/INDEX.LIST", "META-INF/io.netty.versions.properties")
    }

    // The archive the legacy app's own exporter wrote, shared with the core import tests.
    sourceSets["androidTest"].assets.srcDir("../core/src/test/resources/migration")
    if (!leafwake) sourceSets["androidTest"].kotlin.srcDir("src/withCastAndroidTest/kotlin")
    if (leafwake) sourceSets["main"].assets.srcDir("src/noCast/assets")
    sourceSets["main"].kotlin.srcDir(if (leafwake) "src/noCast/kotlin" else "src/withCast/kotlin")
    if (!leafwake) {
        sourceSets["debug"].manifest.srcFile("src/withCast/AndroidManifest.xml")
        sourceSets["release"].manifest.srcFile("src/withCast/AndroidManifest.xml")
    }

    testOptions {
        animationsDisabled = true
        execution = "ANDROIDX_TEST_ORCHESTRATOR"
        unitTests.isReturnDefaultValues = true
    }
}

kotlin { jvmToolchain(17) }

dependencies {
    implementation(project(":core"))

    val composeBom = platform("androidx.compose:compose-bom:2025.12.00")
    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation("androidx.core:core-ktx:1.17.0")
    implementation("androidx.activity:activity-compose:1.12.2")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")
    implementation("androidx.lifecycle:lifecycle-process:2.10.0")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material3:material3-window-size-class")
    implementation("androidx.compose.material:material-icons-extended")
    debugImplementation("androidx.compose.ui:ui-tooling")
    implementation("com.google.android.material:material:1.13.0")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-guava:1.10.2")
    implementation("androidx.browser:browser:1.9.0")
    implementation("androidx.work:work-runtime-ktx:2.11.0")

    implementation("androidx.media3:media3-exoplayer:1.9.0")
    implementation("androidx.media3:media3-session:1.9.0")
    implementation("androidx.media3:media3-datasource-okhttp:1.9.0")
    implementation("androidx.media3:media3-exoplayer-hls:1.9.0")
    if (!leafwake) implementation("androidx.media3:media3-cast:1.9.0")

    implementation("io.coil-kt.coil3:coil-compose:3.3.0")
    implementation("io.coil-kt.coil3:coil-network-okhttp:3.3.0")

    implementation("io.socket:socket.io-client:2.1.2") {
        exclude(group = "org.json", module = "json")
    }

    testImplementation("junit:junit:4.13.2")
    androidTestUtil("androidx.test:orchestrator:1.6.1")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test:rules:1.7.0")
    androidTestImplementation("androidx.test.uiautomator:uiautomator:2.3.0")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("com.google.android.apps.common.testing.accessibility.framework:accessibility-test-framework:4.1.1")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}

tasks.register("writeRuntimeInventory") {
    doLast {
        val artifacts = configurations.getByName("releaseRuntimeClasspath").resolvedConfiguration.resolvedArtifacts
        val output = layout.buildDirectory.file("reports/release-runtime.tsv").get().asFile
        output.parentFile.mkdirs()
        output.writeText(artifacts.map { "${it.moduleVersion.id}\t${it.file.absolutePath}" }.distinct().sorted().joinToString("\n") + "\n")
        println("Runtime inventory: $output")
    }
}
