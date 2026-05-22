package dev.handrail.bugreporter;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.util.Base64;
import android.view.View;

import java.io.ByteArrayOutputStream;
import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

public class HandrailBugReporterPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware {
  private static final int MAX_SCREENSHOT_DIMENSION = 1280;
  private static final int JPEG_QUALITY = 72;

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
    Bitmap outputBitmap = null;
    try {
      bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
      Canvas canvas = new Canvas(bitmap);
      canvas.drawColor(Color.WHITE);
      rootView.draw(canvas);

      outputBitmap = scaledBitmap(bitmap);
      ByteArrayOutputStream output = new ByteArrayOutputStream();
      outputBitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, output);

      Map<String, Object> response = new HashMap<>();
      response.put("base64", Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP));
      response.put("filename", "mobile-screenshot.jpg");
      response.put("mimeType", "image/jpeg");
      result.success(response);
    } catch (Exception error) {
      result.error("CAPTURE_FAILED", error.getClass().getSimpleName(), null);
    } finally {
      if (outputBitmap != null && outputBitmap != bitmap) {
        outputBitmap.recycle();
      }
      if (bitmap != null) {
        bitmap.recycle();
      }
    }
  }

  private Bitmap scaledBitmap(Bitmap source) {
    int width = source.getWidth();
    int height = source.getHeight();
    int largestSide = Math.max(width, height);
    if (largestSide <= MAX_SCREENSHOT_DIMENSION) {
      return source;
    }
    float scale = (float) MAX_SCREENSHOT_DIMENSION / (float) largestSide;
    int scaledWidth = Math.max(1, Math.round(width * scale));
    int scaledHeight = Math.max(1, Math.round(height * scale));
    return Bitmap.createScaledBitmap(source, scaledWidth, scaledHeight, true);
  }
}
