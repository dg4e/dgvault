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

    // Some Flutter plugins (e.g. file_picker 8.x) still compile against an older
    // Android API than the app's compileSdk (36), which AGP rejects as an error.
    // Force every Android library subproject up to the app's compileSdk. This
    // afterEvaluate is registered here (before evaluationDependsOn below forces
    // evaluation) so it runs after each plugin's own android {} block.
    afterEvaluate {
        extensions.findByType(com.android.build.api.dsl.LibraryExtension::class.java)
            ?.let { ext ->
                if ((ext.compileSdk ?: 0) < 36) {
                    ext.compileSdk = 36
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
