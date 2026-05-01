// 概要: Android プロジェクトのルート build script。
//       Kotlin + Jetpack Compose + Maestro E2E を前提にした最小構成。
plugins {
    id("com.android.application") version "8.7.0" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.1.0" apply false
}
