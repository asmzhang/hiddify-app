import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/utils/utils.dart';

abstract class Constants {
  static const appName = "Hiddify";
  static const githubUrl = "https://github.com/hiddify/hiddify-next";
  static const licenseUrl = "https://github.com/hiddify/hiddify-next?tab=License-1-ov-file#readme";
  static const donationUrl = "https://hiddify.com/donation-and-support/";
  static const githubReleasesApiUrl = "https://api.github.com/repos/hiddify/hiddify-next/releases";
  static const githubLatestReleaseUrl = "https://github.com/hiddify/hiddify-app/releases/latest";
  static const appCastUrl = "https://raw.githubusercontent.com/hiddify/hiddify-next/main/appcast.xml";
  static const telegramChannelUrl = "https://t.me/hiddify";
  static const privacyPolicyUrl = "https://hiddify.com/privacy-policy/";
  static const termsAndConditionsUrl = "https://hiddify.com/terms/";
  // FAQ 入口（NekoBox `MainActivity.kt:343` 的 nav_faq → launchCustomTab）。
  // 本项目是 NekoBox 壳，文档站也照它的规格指向 matsuridayo.github.io。
  static const faqUrl = "https://matsuridayo.github.io/";
  static const cfWarpPrivacyPolicy = "https://www.cloudflare.com/application/privacypolicy/";
  static const cfWarpTermsOfService = "https://www.cloudflare.com/application/terms/";
}

const kAnimationDuration = Duration(milliseconds: 250);

abstract class AddProfileModalConst {
  static const fixBtnsGap = 16.0;
  // gapCount = 按钮数 + 1（首尾各一个间距）；itemCount = 按钮数。
  // 批次 3 加了「手动输入（Manual Settings）」按钮 ⇒ 手机 5 项 / 桌面 4 项（桌面无扫码）。
  static const fixBtnsGapCount = 6;
  static const fixBtnsGapCountDesktop = 5;
  static const fixBtnsItemCount = 5;
  static const fixBtnsItemCountDesktop = 4;
  static const navBarGap = 16.0;
  static const navBarBottomGap = 4.0;
  //switch default height
  static const navBarcontentHeight = 32.0;
  static const navBarHeight = navBarGap + navBarBottomGap + navBarcontentHeight;
}

abstract class AlertDialogConst {
  static const minWidth = 280.0;
  static const maxWidth = 560.0;
  static const boxConstraints = BoxConstraints(minWidth: minWidth, maxWidth: maxWidth);
}

abstract class BottomSheetConst {
  static const maxWidth = 456.0;
  static const boxConstraints = BoxConstraints(maxWidth: maxWidth);
  static const borderRadius = BorderRadius.vertical(top: Radius.circular(32));
}

abstract class IntroConst {
  static const maxwidth = 620;
  static const termsAndConditionsKey = 'terms-and-conditions';
  static const githubKey = 'github';
  static const licenseKey = 'license';
  static const url = <String, String>{
    IntroConst.termsAndConditionsKey: Constants.termsAndConditionsUrl,
    IntroConst.githubKey: Constants.githubUrl,
    IntroConst.licenseKey: Constants.licenseUrl,
  };
}

abstract class WarpConst {
  static const warpConsentGiven = "warp-consent-given";
  static const warpTermsOfServiceKey = 'warp-terms-of-service';
  static const warpPrivacyPolicyKey = 'warp-privacy-policy';
  static const url = <String, String>{
    WarpConst.warpTermsOfServiceKey: Constants.cfWarpTermsOfService,
    WarpConst.warpPrivacyPolicyKey: Constants.cfWarpPrivacyPolicy,
  };
}

abstract class PsiphonConst {
  static const psiphonConsentGiven = "psiphon-consent-given";
  static const psiphonTermsOfServiceKey = 'psiphon-terms-of-service';
  static const psiphonPrivacyPolicyKey = 'psiphon-privacy-policy';
  static const url = <String, String>{
    PsiphonConst.psiphonTermsOfServiceKey: "https://psiphon.ca/en/license.html",
    PsiphonConst.psiphonPrivacyPolicyKey: "https://psiphon.ca/en/privacy.html",
  };
}

abstract class KeyboardConst {
  static final allArrows = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  };
  static final horizontalArrows = {LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight};
  static final verticalArrows = {LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown};
  static final select = {LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.tab};
}

abstract class ChainConst {
  static IconData iconByPlatform() {
    if (PlatformUtils.isAndroid) return Icons.phone_android;
    if (PlatformUtils.isIOS) return Icons.phone_iphone;
    if (PlatformUtils.isWeb) return Icons.web;
    // Desktops
    return Icons.laptop;
  }

  static Color finalIpColor(ThemeData theme) =>
      theme.brightness == Brightness.dark ? const Color(0xFF99AD7A) : const Color.fromARGB(255, 87, 136, 13);
  static const warpColor = Color(0xFFF6821F);
  static const psiphonColor = Color(0xFFD52027);
  static const profileColor = Color(0xFF3282B8);

  static const finalIpDuration = Duration(milliseconds: 500);
}
