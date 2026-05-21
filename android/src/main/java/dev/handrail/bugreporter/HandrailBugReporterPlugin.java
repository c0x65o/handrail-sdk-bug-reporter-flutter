package dev.handrail.bugreporter;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.util.Base64;
import android.view.View;

import java.io.ByteArrayOutputStream;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

public class HandrailBugReporterPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware {
  private MethodChannel screenshotChannel;
  private Activity activity;

  @Override
  public void onAttachedToEngine(FlutterPluginBinding binding) {
    screenshotChannel = new MethodChannel(
        binding.getBinaryMessenger(),
        "dev.handrail/bug_reporter/screenshot"
    );
    screenshotChannel.setMethodCallHandler(this);
  }

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {
    if (screenshotChannel != null) {
      screenshotChannel.setMethodCallHandler(null);
      screenshotChannel = null;
    }
  }

  @Override
  public void onMethodCall(MethodCall call, Result result) {
    if (!"captureScreenshot".equals(call.method)) {
      result.notImplemented();
      return;
    }
    captureScreenshot(result);
  }

  @Override
  public void onAttachedToActivity(ActivityPluginBinding binding) {
    activity = binding.getActivity();
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    activity = null;
  }

  @Override
  public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
    activity = binding.getActivity();
  }

  @Override
  public void onDetachedFromActivity() {
    activity = null;
  }

  private void captureScreenshot(Result result) {
    if (activity == null || activity.getWindow() == null) {
      result.error("NO_ACTIVITY", "No Android activity is attached.", null);
      return;
    }

    View rootView = activity.getWindow().getDecorView().getRootView();
    int width = rootView.getWidth();
    int height = rootView.getHeight();
    if (width <= 0 || height <= 0) {
      result.error("VIEW_NOT_READY", "The Android root view is not ready.", null);
      return;
    }

    Bitmap bitmap = null;
    try {
      bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
      Canvas canvas = new Canvas(bitmap);
      rootView.draw(canvas);

      ByteArrayOutputStream output = new ByteArrayOutputStream();
      bitmap.compress(Bitmap.CompressFormat.PNG, 100, output);
      result.success(Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP));
    } catch (Exception error) {
      result.error("CAPTURE_FAILED", error.getClass().getSimpleName(), null);
    } finally {
      if (bitmap != null) {
        bitmap.recycle();
      }
    }
  }
}
