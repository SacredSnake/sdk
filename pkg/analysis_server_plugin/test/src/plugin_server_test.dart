// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:analysis_server_plugin/src/plugin_server.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart' as protocol;
import 'package:analyzer_plugin/protocol/protocol_generated.dart' as protocol;
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'lint_rules.dart';
import 'plugin_server_test_base.dart';

void main() async {
  defineReflectiveTests(PluginServerTest);
}

@reflectiveTest
class PluginServerTest extends PluginServerTestBase {
  @override
  Future<void> setUp() async {
    await super.setUp();

    pluginServer = PluginServer(
        resourceProvider: resourceProvider, plugins: [_NoBoolsPlugin()]);
    await startPlugin();
  }

  Future<void> test_handleAnalysisSetContextRoots() async {
    var packagePath = convertPath('/package1');
    var filePath = join(packagePath, 'lib', 'test.dart');
    newFile(filePath, 'bool b = false;');
    var contextRoot = protocol.ContextRoot(packagePath, []);
    await pluginServer.handleAnalysisSetContextRoots(
        protocol.AnalysisSetContextRootsParams([contextRoot]));
    var notification = await channel.notifications.first;
    var params = protocol.AnalysisErrorsParams.fromNotification(notification);
    expect(params.file, convertPath('/package1/lib/test.dart'));
    expect(params.errors, hasLength(1));

    expect(
      params.errors.single,
      isA<protocol.AnalysisError>()
          .having((e) => e.severity, 'severity',
              protocol.AnalysisErrorSeverity.INFO)
          .having(
              (e) => e.type, 'type', protocol.AnalysisErrorType.STATIC_WARNING)
          .having((e) => e.message, 'message', 'No bools message'),
    );
  }

  Future<void> test_handleEditGetFixes() async {
    var packagePath = convertPath('/package1');
    var filePath = join(packagePath, 'lib', 'test.dart');
    newFile(filePath, 'bool b = false;');
    var contextRoot = protocol.ContextRoot(packagePath, []);
    await pluginServer.handleAnalysisSetContextRoots(
        protocol.AnalysisSetContextRootsParams([contextRoot]));

    var result = await pluginServer.handleEditGetFixes(
        protocol.EditGetFixesParams(filePath, 'bool b = '.length));
    var fixes = result.fixes;
    // We expect 1 fix because neither `IgnoreDiagnosticOnLine` nor
    // `IgnoreDiagnosticInFile` are registered by the plugin.
    // TODO(srawlins): Investigate whether they should be.
    expect(fixes, hasLength(1));
    expect(fixes[0].fixes, hasLength(1));
  }
}

class _NoBoolsPlugin extends Plugin {
  @override
  void register(PluginRegistry registry) {
    registry.registerRule(NoBoolsRule());
    registry.registerFixForRule(NoBoolsRule.code, _WrapInQuotes.new);
  }
}

class _WrapInQuotes extends ResolvedCorrectionProducer {
  static const _wrapInQuotesKind =
      FixKind('dart.fix.wrapInQuotes', 50, 'Wrap in quotes');

  _WrapInQuotes({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.acrossFiles;

  @override
  FixKind get fixKind => _wrapInQuotesKind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    var literal = node;
    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleInsertion(literal.offset, "'");
      builder.addSimpleInsertion(literal.end, "'");
    });
  }
}
