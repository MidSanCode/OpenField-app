allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    afterEvaluate {
        if (plugins.hasPlugin("com.android.library")) {
            extensions.configure<com.android.build.api.dsl.LibraryExtension> {
                compileSdk = 36
                // Keep Java bytecode at 17 across every plugin so the Java and
                // Kotlin compile tasks of each plugin agree. Without this,
                // plugins that hardcode older values (flutter_js ships
                // jvmTarget 1.8 / Java 11) fail with "Inconsistent JVM Target
                // Compatibility Between Java and Kotlin Tasks".
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
        }
        // Align the Kotlin JVM target of every plugin with the Java target
        // above (and with the app module's 17). KotlinAndroidProjectExtension
        // is resolved by name here because plugin classpaths differ between
        // subprojects.
        if (plugins.hasPlugin("org.jetbrains.kotlin.android")) {
            extensions.findByType(org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension::class.java)?.let { ext ->
                ext.compilerOptions {
                    jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
                }
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
