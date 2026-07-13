allprojects {
    repositories {
        google()
        mavenCentral()
        maven("https://chaquo.com/maven")
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
    project.evaluationDependsOn(":app")
}
subprojects {
    fun configureAndroid(proj: Project) {
        val android = proj.extensions.findByName("android")
        if (android != null) {
            val baseExt = android as? com.android.build.gradle.BaseExtension
            if (baseExt != null) {
                baseExt.compileSdkVersion(36)
                baseExt.defaultConfig.minSdk = 24
            }
        }
    }
    if (state.executed) {
        configureAndroid(this)
    } else {
        afterEvaluate {
            configureAndroid(this)
        }
    }
}

subprojects {
    configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "com.chaquo.python") {
                useVersion("17.0.0")
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
