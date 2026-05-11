// 概要: Android アプリのエントリポイント。
//       Jetpack Compose を用いて最小限の画面を描画する。
//       UI / UX 規約は .my-harness/rules/design.md を参照（shokasonjuku UX 心理学 47 原則）。

package com.example.harness

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview

/**
 * アプリ起動時に最初に表示されるアクティビティ。
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    HelloHarness()
                }
            }
        }
    }
}

/**
 * 仮の表示用 Composable。プロダクト要件に応じて差し替えること。
 */
@Composable
fun HelloHarness() {
    Text(text = "ハーネスへようこそ")
}

@Preview(showBackground = true)
@Composable
fun HelloHarnessPreview() {
    MaterialTheme { HelloHarness() }
}
