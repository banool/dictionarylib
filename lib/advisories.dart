import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;

import 'l10n/app_localizations.dart';
import 'common.dart';
import 'globals.dart';

class Advisory {
  String date;
  List<String> lines;

  // Optional inclusive app-version bounds. An advisory is only shown when the
  // running app's version is within [minVersion, maxVersion]. Either (or both)
  // may be null, meaning "no lower/upper bound". See
  // advisoryAppliesToCurrentVersion.
  String? minVersion;
  String? maxVersion;

  MarkdownBody asMarkdown() {
    return MarkdownBody(data: lines.join("\n"));
  }

  Advisory({
    required this.date,
    required this.lines,
    this.minVersion,
    this.maxVersion,
  });
}

// Returns true if [advisory] should be shown to the running build, i.e. the
// app's version falls within the advisory's [Advisory.minVersion] /
// [Advisory.maxVersion] range (both inclusive, both optional). If we couldn't
// determine our own version we fail open and show it — better a stray
// announcement than silently swallowing an important one.
bool advisoryAppliesToCurrentVersion(Advisory advisory) {
  if (advisory.minVersion == null && advisory.maxVersion == null) {
    return true;
  }
  var current = packageInfo?.version;
  if (current == null) {
    return true;
  }
  if (advisory.minVersion != null &&
      compareVersions(current, advisory.minVersion!) < 0) {
    return false;
  }
  if (advisory.maxVersion != null &&
      compareVersions(current, advisory.maxVersion!) > 0) {
    return false;
  }
  return true;
}

// Compares two dotted version strings (e.g. "2.0.0") numerically, part by
// part. Returns a negative number if [a] is older than [b], zero if they're
// equal, a positive number if [a] is newer. Any "+build" suffix is ignored,
// missing trailing parts count as 0 (so "2.0" == "2.0.0"), and non-numeric
// parts count as 0 so a malformed bound can never accidentally hide an
// advisory.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .split("+")
      .first
      .split(".")
      .map((p) => int.tryParse(p.trim()) ?? 0)
      .toList();
  var pa = parts(a);
  var pb = parts(b);
  var length = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < length; i++) {
    var x = i < pa.length ? pa[i] : 0;
    var y = i < pb.length ? pb[i] : 0;
    if (x != y) {
      return x < y ? -1 : 1;
    }
  }
  return 0;
}

class AdvisoriesResponse {
  List<Advisory> advisories;
  bool newAdvisories;

  AdvisoriesResponse({
    required this.advisories,
    required this.newAdvisories,
  });
}

// Returns the advisories and whether there is a new advisory. It returns them
// in order from old to new. If we failed to lookup the advisories we return
// null.
Future<AdvisoriesResponse?> getAdvisories(Uri advisoriesFileUri) async {
  printAndLog("Fetching advisories");

  // Pull the number of advisories we've seen in the past from storage.
  int numKnownAdvisories = sharedPreferences.getInt(KEY_ADVISORY_VERSION) ?? 0;

  // Get the advisories file.
  String? rawData;
  try {
    var result = await http
        .get(advisoriesFileUri)
        .timeout(const Duration(milliseconds: 2250));
    rawData = result.body;
  } catch (e) {
    printAndLog("Failed to get advisory: $e");
    return null;
  }

  // Each advisory is a list of strings, the lines from within the section.
  List<Advisory> advisories = [];
  var inSection = false;
  List<String> currentLines = [];
  String? currentDate;
  String? currentMinVersion;
  String? currentMaxVersion;
  for (var line in rawData.split("\n")) {
    // Skip comment lines.
    if (line.startsWith("////")) {
      continue;
    }

    // Skip empty lines if we're not in a action.
    if (line.length == 1 && line.endsWith("\n") && !inSection) {
      continue;
    }

    // Handle the start of a section.
    if (line.startsWith("START===")) {
      inSection = true;
      continue;
    }

    // Handle the end of a section.
    if (line.startsWith("END===")) {
      var advisory = Advisory(
        date: currentDate!,
        lines: currentLines,
        minVersion: currentMinVersion,
        maxVersion: currentMaxVersion,
      );
      // Only keep advisories whose version range covers this build. One with
      // no MINVERSION/MAXVERSION applies to everyone.
      if (advisoryAppliesToCurrentVersion(advisory)) {
        advisories.add(advisory);
      }
      currentLines = [];
      currentDate = null;
      currentMinVersion = null;
      currentMaxVersion = null;
      inSection = false;
      continue;
    }

    // Handle the date.
    if (line.startsWith("DATE===")) {
      currentDate = line.substring("DATE===".length);
      continue;
    }

    // Handle the optional inclusive app-version bounds. These let a newer
    // announcement target newer app versions; older versions parsing the same
    // section simply skip it (see advisoryAppliesToCurrentVersion).
    if (line.startsWith("MINVERSION===")) {
      currentMinVersion = line.substring("MINVERSION===".length).trim();
      continue;
    }
    if (line.startsWith("MAXVERSION===")) {
      currentMaxVersion = line.substring("MAXVERSION===".length).trim();
      continue;
    }

    if (inSection) {
      currentLines.add(line);
    }
  }

  bool newAdvisories = numKnownAdvisories < advisories.length;

  // Write back the new latest advisories version we'v seen.
  await sharedPreferences.setInt(KEY_ADVISORY_VERSION, advisories.length);

  printAndLog(
      "Fetched ${advisories.length} advisories. There are new advisories: $newAdvisories");

  return AdvisoriesResponse(
      advisories: advisories, newAdvisories: newAdvisories);
}

void showAdvisoryDialog({BuildContext? context}) {
  showDialog(
      context: context ?? rootNavigatorKey.currentContext!,
      builder: (context) {
        final maxHeight = MediaQuery.of(context).size.height * 0.7;
        return AlertDialog(
            title: Text(
                DictLibLocalizations.of(context)?.newsTitle ?? "Advisories"),
            content: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(child: getAdvisoriesInner())));
      });
}

Widget getAdvisoriesInner() {
  var advisories = advisoriesResponse!.advisories.reversed.toList();

  List<Widget> children = [];
  for (var advisory in advisories) {
    children.add(Padding(
        padding: const EdgeInsets.only(left: 0),
        child: Text(
          advisory.date,
          textAlign: TextAlign.start,
        )));
    children.add(advisory.asMarkdown());
    // Add padding between after each item. We remove the last padding later.
    children.add(const SizedBox(height: 40));
  }

  return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children.sublist(0, children.length - 1));
}
