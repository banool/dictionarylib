import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;

import 'l10n/app_localizations.dart';
import 'common.dart';
import 'globals.dart';

class Advisory {
  String date;
  List<String> lines;

  MarkdownBody asMarkdown() {
    return MarkdownBody(data: lines.join("\n"));
  }

  Advisory({
    required this.date,
    required this.lines,
  });
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
    var result =
        await http.get(advisoriesFileUri).timeout(const Duration(seconds: 3));
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
      advisories.add(Advisory(date: currentDate!, lines: currentLines));
      currentLines = [];
      currentDate = null;
      inSection = false;
      continue;
    }

    // Handle the date.
    if (line.startsWith("DATE===")) {
      currentDate = line.substring("DATE===".length);
      continue;
    }

    if (inSection) {
      currentLines.add(line);
    }
  }

  bool newAdvisories = numKnownAdvisories < advisories.length;

  // Write back the new latest advisories version we'v seen.
  await sharedPreferences.setInt(KEY_ADVISORY_VERSION, advisories.length);

  printAndLog("Fetched ${advisories.length} advisories");

  return AdvisoriesResponse(
      advisories: advisories, newAdvisories: newAdvisories);
}

void showAdvisoryDialog() {
  showDialog(
      context: rootNavigatorKey.currentContext!,
      builder: (context) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.newsTitle),
          content: SingleChildScrollView(child: getAdvisoriesInner())));
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
