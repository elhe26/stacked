import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'package:stacked/stacked_annotations.dart';
import 'package:stacked_generator/import_resolver.dart';
import 'package:stacked_generator/src/generators/enums/dependency_type.dart';
import 'package:stacked_generator/src/generators/getit/dependency_config.dart';
import 'package:stacked_generator/src/generators/getit/stacked_locator_content_generator.dart';
import 'package:stacked_generator/src/generators/getit/services_config.dart';
import 'package:stacked_generator/utils.dart';

const stackedRouteChecker = TypeChecker.fromRuntime(StackedRoute);

class StackedLocatorGenerator extends GeneratorForAnnotation<StackedApp> {
  @override
  dynamic generateForAnnotatedElement(
    Element element,
    ConstantReader stackedApplication,
    BuildStep buildStep,
  ) async {
    var libs = await buildStep.resolver.libraries.toList();
    var importResolver = ImportResolver(libs, element.source?.uri.path ?? '');

    final servicesConfig = stackedApplication.peek('dependencies')?.listValue;
    if (servicesConfig != null) {
      List<DependencyConfig> services = <DependencyConfig>[];
      // Convert the services config into Services configuration
      for (final serviceConfig in servicesConfig) {
        final serialisedServiceConfig = _readDependencyConfig(
          dependencyConfig: serviceConfig,
          importResolver: importResolver,
        );
        services.add(serialisedServiceConfig);
      }

      return StackedLocatorContentGenerator(ServicesConfig(services: services))
          .generate();
    }
  }

  DependencyConfig _readDependencyConfig({
    required DartObject dependencyConfig,
    required ImportResolver importResolver,
  }) {
    var dependencyReader = ConstantReader(dependencyConfig);
    // Get the type of the service that we want to register
    final DartType? dependencyClassType =
        dependencyReader.read('classType').typeValue;

    final DartType? dependencyAbstractedClassType =
        dependencyReader.peek('asType')?.typeValue;

    throwIf(
      dependencyClassType == null,
      '🛑 No dependency class Type defined for ${dependencyConfig.toString()}. Please make sure that any of the services provided to the services list in the StackedApp annotation has a service provided. Please see the documentation for stacked_generator if you don\'t know what this means.',
    );

    final classElement = dependencyClassType!.element as ClassElement?;

    throwIf(
      classElement == null,
      '🛑 ${toDisplayString(dependencyClassType)} is not a class element. All services should be classes. We don\'t register individual values for global access through the locator. Make sure the value provided as your service type is a class.',
    );

    // Get the import of the class type that's defined for the service
    final import = importResolver.resolve(classElement!);

    final abstractedClassElement =
        dependencyAbstractedClassType?.element as ClassElement?;

    final abstractedImport = importResolver.resolve(abstractedClassElement);

    final className = toDisplayString(dependencyClassType);

    final abstractedTypeClassName = dependencyAbstractedClassType != null
        ? toDisplayString(dependencyAbstractedClassType)
        : null;

    // NOTE: This can be used for actual dependency inject. We do service location instead.
    final constructor = classElement.unnamedConstructor;

    final serviceType = _getDependencyType(dependencyReader);

    String? presolveFunction;
    if (serviceType == DependencyType.PresolvedSingleton) {
      final ConstantReader? presolveUsing =
          dependencyReader.peek('presolveUsing');
      final presolveObject = presolveUsing?.objectValue.toFunctionValue();
      presolveFunction = presolveObject?.displayName;
    }

    String? resolveFunction;
    if (serviceType == DependencyType.LazySingleton ||
        serviceType == DependencyType.Singleton) {
      final ConstantReader? resolveUsing =
          dependencyReader.peek('resolveUsing');
      final resolveObject = resolveUsing?.objectValue.toFunctionValue();
      resolveFunction = resolveObject?.displayName;
    }

    return DependencyConfig(
      className: className,
      abstractedTypeClassName: abstractedTypeClassName,
      import: import,
      abstractedImport: abstractedImport,
      type: serviceType,
      presolveFunction: presolveFunction,
      resolveFunction: resolveFunction,
    );
  }

  DependencyType _getDependencyType(ConstantReader serviceReader) {
    if (serviceReader.instanceOf(TypeChecker.fromRuntime(Factory))) {
      return DependencyType.Factory;
    }
    if (serviceReader.instanceOf(TypeChecker.fromRuntime(Singleton))) {
      return DependencyType.Singleton;
    }
    if (serviceReader.instanceOf(TypeChecker.fromRuntime(LazySingleton))) {
      return DependencyType.LazySingleton;
    }
    if (serviceReader.instanceOf(TypeChecker.fromRuntime(Presolve))) {
      return DependencyType.PresolvedSingleton;
    }

    return DependencyType.Singleton;
  }
}
