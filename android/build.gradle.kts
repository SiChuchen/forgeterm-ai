allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val isWindows = System.getProperty("os.name").startsWith("Windows", ignoreCase = true)

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
    project.evaluationDependsOn(":app")
}

subprojects {
    if (isWindows) {
        // Windows + AGP occasionally leaves lintVital caches locked in plugin subprojects
        // during release builds. We already run Flutter analyze/test separately, so skip
        // lintVital-only tasks locally to keep release builds reproducible.
        tasks.matching { task ->
            task.name.startsWith("lintVital", ignoreCase = true)
        }.configureEach {
            enabled = false
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
