allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    // EXPERT FIX 1: The Namespace Injector (Solves the crash you just got)
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
            if (namespace == null) {
                // Dynamically creates a namespace for old plugins like Isar
                namespace = "dev.flutter." + project.name.replace('-', '_')
            }
        }
    }

    // EXPERT FIX 2: The SDK 36 Nuke (Solves the original lStar crash)
    if (project.name != "app") {
        afterEvaluate {
            val androidExt = project.extensions.findByName("android") as? com.android.build.gradle.BaseExtension
            androidExt?.compileSdkVersion(36)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}