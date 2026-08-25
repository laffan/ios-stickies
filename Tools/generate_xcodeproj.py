#!/usr/bin/env python3
"""Generate Stickies.xcodeproj.

The project is committed, so you only need this when files are added, removed
or moved:

    python3 Tools/generate_xcodeproj.py

Object identifiers are derived from stable hashes of each object's role, so
regenerating produces a byte-identical project when nothing has changed and a
readable diff when something has.
"""

import hashlib
import os
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_NAME = "Stickies"
APP_TARGET = "Stickies"
WIDGET_TARGET = "StickiesWidgets"
PROJECT_DIR = os.path.join(ROOT, PROJECT_NAME + ".xcodeproj")

FILE_TYPES = {
    ".swift": "sourcecode.swift",
    ".plist": "text.plist.xml",
    ".entitlements": "text.plist.entitlements",
    ".xcassets": "folder.assetcatalog",
    ".xcconfig": "text.xcconfig",
    ".md": "net.daringfireball.markdown",
    ".json": "text.json",
    ".py": "text.script.python",
}


def oid(*parts):
    """A stable 24-hex-character object id."""
    digest = hashlib.md5("::".join(parts).encode("utf-8")).hexdigest()
    return digest[:24].upper()


def quote(value):
    if value == "":
        return '""'
    allowed = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./")
    if all(character in allowed for character in value):
        return value
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return '"%s"' % escaped


def settings_lines(settings, indent):
    """Render a build-settings dictionary, sorted for stable diffs."""
    pad = "\t" * indent
    lines = []
    for key in sorted(settings):
        value = settings[key]
        if isinstance(value, list):
            lines.append("%s%s = (" % (pad, quote(key)))
            for item in value:
                lines.append("%s\t%s," % (pad, quote(item)))
            lines.append("%s);" % pad)
        else:
            lines.append("%s%s = %s;" % (pad, quote(key), quote(value)))
    return lines


# ---------------------------------------------------------------------------
# Source inventory
# ---------------------------------------------------------------------------

def collect(directory, extensions=None, stop_at_bundles=True):
    """Files under `directory`, relative to the repo root, sorted."""
    found = []
    base = os.path.join(ROOT, directory)
    for current, subdirs, names in os.walk(base):
        if stop_at_bundles and current.endswith(".xcassets"):
            subdirs[:] = []
            continue
        subdirs[:] = [d for d in sorted(subdirs) if not d.startswith(".")]
        # An asset catalogue is referenced as a single folder, not as files.
        if extensions is None:
            # Asset catalogues are referenced as a single folder.
            for name in sorted(subdirs):
                if name.endswith(".xcassets"):
                    found.append(os.path.relpath(os.path.join(current, name), ROOT))
        for name in sorted(names):
            if name.startswith("."):
                continue
            extension = os.path.splitext(name)[1]
            if extensions is not None and extension not in extensions:
                continue
            found.append(os.path.relpath(os.path.join(current, name), ROOT))
    return sorted(set(found))


class Project:
    def __init__(self):
        self.shared_sources = collect("Shared", {".swift"})
        self.app_sources = collect("App", {".swift"})
        self.widget_sources = collect("Widgets", {".swift"})
        self.app_resources = [p for p in collect("App") if p.endswith(".xcassets")]
        self.widget_resources = [p for p in collect("Widgets") if p.endswith(".xcassets")]
        self.support_files = [
            "Config/Base.xcconfig",
            "App/Info.plist",
            "App/Stickies-iOS.entitlements",
            "App/Stickies-macOS.entitlements",
            "Widgets/Info.plist",
            "Widgets/StickiesWidgets-iOS.entitlements",
            "Widgets/StickiesWidgets-macOS.entitlements",
            "README.md",
        ] + collect("Tools", {".py"})
        self.support_files = [p for p in self.support_files if os.path.exists(os.path.join(ROOT, p))]

        self.all_paths = sorted(set(
            self.shared_sources
            + self.app_sources
            + self.widget_sources
            + self.app_resources
            + self.widget_resources
            + self.support_files
        ))

        # Object ids
        self.project_id = oid("project")
        self.main_group = oid("group", "<root>")
        self.products_group = oid("group", "<products>")
        self.app_target = oid("target", APP_TARGET)
        self.widget_target = oid("target", WIDGET_TARGET)
        self.app_product = oid("product", APP_TARGET)
        self.widget_product = oid("product", WIDGET_TARGET)
        self.xcconfig_ref = self.file_ref("Config/Base.xcconfig")

    # -- ids ---------------------------------------------------------------

    def file_ref(self, path):
        return oid("fileref", path)

    def build_file(self, path, target):
        return oid("buildfile", target, path)

    # -- sections ----------------------------------------------------------

    def build_file_section(self):
        entries = []
        for target, paths in (
            (APP_TARGET, self.shared_sources + self.app_sources + self.app_resources),
            (WIDGET_TARGET, self.shared_sources + self.widget_sources + self.widget_resources),
        ):
            for path in paths:
                entries.append(
                    "\t\t%s /* %s in %s */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };"
                    % (
                        self.build_file(path, target),
                        os.path.basename(path),
                        "Resources" if path.endswith(".xcassets") else "Sources",
                        self.file_ref(path),
                        os.path.basename(path),
                    )
                )
        # The app embeds the widget extension.
        entries.append(
            "\t\t%s /* %s.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; "
            "fileRef = %s /* %s.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };"
            % (oid("embed", WIDGET_TARGET), WIDGET_TARGET, self.widget_product, WIDGET_TARGET)
        )
        return self.section("PBXBuildFile", sorted(entries))

    def file_reference_section(self):
        entries = []
        for path in self.all_paths:
            extension = os.path.splitext(path)[1]
            file_type = FILE_TYPES.get(extension, "text")
            entries.append(
                "\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; "
                "name = %s; path = %s; sourceTree = \"<group>\"; };"
                % (
                    self.file_ref(path),
                    os.path.basename(path),
                    file_type,
                    quote(os.path.basename(path)),
                    quote(os.path.basename(path)),
                )
            )
        entries.append(
            "\t\t%s /* %s.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; "
            "includeInIndex = 0; path = %s.app; sourceTree = BUILT_PRODUCTS_DIR; };"
            % (self.app_product, APP_TARGET, APP_TARGET)
        )
        entries.append(
            "\t\t%s /* %s.appex */ = {isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; "
            "includeInIndex = 0; path = %s.appex; sourceTree = BUILT_PRODUCTS_DIR; };"
            % (self.widget_product, WIDGET_TARGET, WIDGET_TARGET)
        )
        return self.section("PBXFileReference", sorted(entries))

    def group_section(self):
        """Mirror the directory tree as Xcode groups."""
        tree = {}
        for path in self.all_paths:
            parts = path.split("/")
            node = tree
            for part in parts[:-1]:
                node = node.setdefault(part, {})
            node.setdefault("__files__", []).append(path)

        entries = []

        def emit(node, prefix):
            group_id = oid("group", prefix or "<root>")
            children = []
            for name in sorted(k for k in node if k != "__files__"):
                child_prefix = "%s/%s" % (prefix, name) if prefix else name
                children.append((name, emit(node[name], child_prefix)))
            for path in sorted(node.get("__files__", [])):
                children.append((os.path.basename(path), self.file_ref(path)))

            lines = ["\t\t%s /* %s */ = {" % (group_id, prefix or PROJECT_NAME)]
            lines.append("\t\t\tisa = PBXGroup;")
            lines.append("\t\t\tchildren = (")
            for name, child_id in children:
                lines.append("\t\t\t\t%s /* %s */," % (child_id, name))
            if not prefix:
                lines.append("\t\t\t\t%s /* Products */," % self.products_group)
            lines.append("\t\t\t);")
            if prefix:
                lines.append("\t\t\tpath = %s;" % quote(os.path.basename(prefix)))
            lines.append("\t\t\tsourceTree = \"<group>\";")
            lines.append("\t\t};")
            entries.append("\n".join(lines))
            return group_id

        emit(tree, "")

        entries.append(
            "\n".join([
                "\t\t%s /* Products */ = {" % self.products_group,
                "\t\t\tisa = PBXGroup;",
                "\t\t\tchildren = (",
                "\t\t\t\t%s /* %s.app */," % (self.app_product, APP_TARGET),
                "\t\t\t\t%s /* %s.appex */," % (self.widget_product, WIDGET_TARGET),
                "\t\t\t);",
                "\t\t\tname = Products;",
                "\t\t\tsourceTree = \"<group>\";",
                "\t\t};",
            ])
        )
        return self.section("PBXGroup", entries)

    def phase(self, isa, target, name, paths, extra=None):
        phase_id = oid("phase", isa, target)
        lines = ["\t\t%s /* %s */ = {" % (phase_id, name)]
        lines.append("\t\t\tisa = %s;" % isa)
        lines.append("\t\t\tbuildActionMask = 2147483647;")
        for key, value in (extra or []):
            lines.append("\t\t\t%s = %s;" % (key, value))
        lines.append("\t\t\tfiles = (")
        for path in paths:
            lines.append(
                "\t\t\t\t%s /* %s */," % (self.build_file(path, target), os.path.basename(path))
            )
        lines.append("\t\t\t);")
        lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        lines.append("\t\t};")
        return phase_id, "\n".join(lines)

    def phases(self):
        sources, frameworks, resources, copies = [], [], [], []
        ids = {}

        for target, source_paths, resource_paths in (
            (APP_TARGET, self.shared_sources + self.app_sources, self.app_resources),
            (WIDGET_TARGET, self.shared_sources + self.widget_sources, self.widget_resources),
        ):
            phase_id, text = self.phase("PBXSourcesBuildPhase", target, "Sources", source_paths)
            ids[(target, "sources")] = phase_id
            sources.append(text)

            phase_id, text = self.phase("PBXFrameworksBuildPhase", target, "Frameworks", [])
            ids[(target, "frameworks")] = phase_id
            frameworks.append(text)

            phase_id, text = self.phase("PBXResourcesBuildPhase", target, "Resources", resource_paths)
            ids[(target, "resources")] = phase_id
            resources.append(text)

        embed_id = oid("phase", "PBXCopyFilesBuildPhase", APP_TARGET)
        copies.append("\n".join([
            "\t\t%s /* Embed Foundation Extensions */ = {" % embed_id,
            "\t\t\tisa = PBXCopyFilesBuildPhase;",
            "\t\t\tbuildActionMask = 2147483647;",
            "\t\t\tdstPath = \"\";",
            "\t\t\tdstSubfolderSpec = 13;",
            "\t\t\tfiles = (",
            "\t\t\t\t%s /* %s.appex in Embed Foundation Extensions */," % (oid("embed", WIDGET_TARGET), WIDGET_TARGET),
            "\t\t\t);",
            "\t\t\tname = \"Embed Foundation Extensions\";",
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;",
            "\t\t};",
        ]))
        ids[(APP_TARGET, "embed")] = embed_id

        return ids, (
            self.section("PBXCopyFilesBuildPhase", copies)
            + self.section("PBXFrameworksBuildPhase", frameworks)
            + self.section("PBXResourcesBuildPhase", resources)
            + self.section("PBXSourcesBuildPhase", sources)
        )

    def target_section(self, phase_ids):
        dependency_id = oid("dependency", WIDGET_TARGET)
        proxy_id = oid("proxy", WIDGET_TARGET)

        proxy = "\n".join([
            "\t\t%s /* PBXContainerItemProxy */ = {" % proxy_id,
            "\t\t\tisa = PBXContainerItemProxy;",
            "\t\t\tcontainerPortal = %s /* Project object */;" % self.project_id,
            "\t\t\tproxyType = 1;",
            "\t\t\tremoteGlobalIDString = %s;" % self.widget_target,
            "\t\t\tremoteInfo = %s;" % WIDGET_TARGET,
            "\t\t};",
        ])
        dependency = "\n".join([
            "\t\t%s /* PBXTargetDependency */ = {" % dependency_id,
            "\t\t\tisa = PBXTargetDependency;",
            "\t\t\ttarget = %s /* %s */;" % (self.widget_target, WIDGET_TARGET),
            "\t\t\ttargetProxy = %s /* PBXContainerItemProxy */;" % proxy_id,
            "\t\t};",
        ])

        def native(target_id, name, product_id, product_type, product_ref_name, phases, dependencies):
            return "\n".join([
                "\t\t%s /* %s */ = {" % (target_id, name),
                "\t\t\tisa = PBXNativeTarget;",
                "\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget \"%s\" */;"
                % (oid("configlist", name), name),
                "\t\t\tbuildPhases = (",
            ] + [
                "\t\t\t\t%s," % phase for phase in phases
            ] + [
                "\t\t\t);",
                "\t\t\tbuildRules = (",
                "\t\t\t);",
                "\t\t\tdependencies = (",
            ] + [
                "\t\t\t\t%s /* PBXTargetDependency */," % dep for dep in dependencies
            ] + [
                "\t\t\t);",
                "\t\t\tname = %s;" % name,
                "\t\t\tproductName = %s;" % name,
                "\t\t\tproductReference = %s /* %s */;" % (product_id, product_ref_name),
                "\t\t\tproductType = \"%s\";" % product_type,
                "\t\t};",
            ])

        app = native(
            self.app_target, APP_TARGET, self.app_product,
            "com.apple.product-type.application", APP_TARGET + ".app",
            [
                phase_ids[(APP_TARGET, "sources")],
                phase_ids[(APP_TARGET, "frameworks")],
                phase_ids[(APP_TARGET, "resources")],
                phase_ids[(APP_TARGET, "embed")],
            ],
            [dependency_id],
        )
        widget = native(
            self.widget_target, WIDGET_TARGET, self.widget_product,
            "com.apple.product-type.app-extension", WIDGET_TARGET + ".appex",
            [
                phase_ids[(WIDGET_TARGET, "sources")],
                phase_ids[(WIDGET_TARGET, "frameworks")],
                phase_ids[(WIDGET_TARGET, "resources")],
            ],
            [],
        )

        return (
            self.section("PBXContainerItemProxy", [proxy])
            + self.section("PBXNativeTarget", [app, widget])
            + self.section("PBXTargetDependency", [dependency])
        )

    def project_object(self):
        return self.section("PBXProject", ["\n".join([
            "\t\t%s /* Project object */ = {" % self.project_id,
            "\t\t\tisa = PBXProject;",
            "\t\t\tattributes = {",
            "\t\t\t\tBuildIndependentTargetsInParallel = 1;",
            "\t\t\t\tLastSwiftUpdateCheck = 1540;",
            "\t\t\t\tLastUpgradeCheck = 1540;",
            "\t\t\t\tTargetAttributes = {",
            "\t\t\t\t\t%s = {" % self.app_target,
            "\t\t\t\t\t\tCreatedOnToolsVersion = 15.4;",
            "\t\t\t\t\t};",
            "\t\t\t\t\t%s = {" % self.widget_target,
            "\t\t\t\t\t\tCreatedOnToolsVersion = 15.4;",
            "\t\t\t\t\t};",
            "\t\t\t\t};",
            "\t\t\t};",
            "\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXProject \"%s\" */;"
            % (oid("configlist", "PROJECT"), PROJECT_NAME),
            "\t\t\tcompatibilityVersion = \"Xcode 14.0\";",
            "\t\t\tdevelopmentRegion = en;",
            "\t\t\thasScannedForEncodings = 0;",
            "\t\t\tknownRegions = (",
            "\t\t\t\ten,",
            "\t\t\t\tBase,",
            "\t\t\t);",
            "\t\t\tmainGroup = %s;" % self.main_group,
            "\t\t\tproductRefGroup = %s /* Products */;" % self.products_group,
            "\t\t\tprojectDirPath = \"\";",
            "\t\t\tprojectRoot = \"\";",
            "\t\t\ttargets = (",
            "\t\t\t\t%s /* %s */," % (self.app_target, APP_TARGET),
            "\t\t\t\t%s /* %s */," % (self.widget_target, WIDGET_TARGET),
            "\t\t\t);",
            "\t\t};",
        ])])

    # -- build configurations ---------------------------------------------

    def configurations(self):
        shared = {
            "ALWAYS_SEARCH_USER_PATHS": "NO",
            "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
            "CLANG_ANALYZER_NONNULL": "YES",
            "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
            "CLANG_ENABLE_MODULES": "YES",
            "CLANG_ENABLE_OBJC_ARC": "YES",
            "CLANG_ENABLE_OBJC_WEAK": "YES",
            "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
            "CLANG_WARN_BOOL_CONVERSION": "YES",
            "CLANG_WARN_COMMA": "YES",
            "CLANG_WARN_CONSTANT_CONVERSION": "YES",
            "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
            "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES_ERROR",
            "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
            "CLANG_WARN_EMPTY_BODY": "YES",
            "CLANG_WARN_ENUM_CONVERSION": "YES",
            "CLANG_WARN_INFINITE_RECURSION": "YES",
            "CLANG_WARN_INT_CONVERSION": "YES",
            "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
            "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
            "CLANG_WARN_OBJC_ROOT_CLASS": "YES_ERROR",
            "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
            "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
            "CLANG_WARN_STRICT_PROTOTYPES": "YES",
            "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
            "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
            "CLANG_WARN_UNREACHABLE_CODE": "YES",
            "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
            "COPY_PHASE_STRIP": "NO",
            "ENABLE_STRICT_OBJC_MSGSEND": "YES",
            "GCC_C_LANGUAGE_STANDARD": "gnu17",
            "GCC_NO_COMMON_BLOCKS": "YES",
            "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
            "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
            "GCC_WARN_UNDECLARED_SELECTOR": "YES",
            "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
            "GCC_WARN_UNUSED_FUNCTION": "YES",
            "GCC_WARN_UNUSED_VARIABLE": "YES",
            "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
            "MTL_FAST_MATH": "YES",
            "SWIFT_EMIT_LOC_STRINGS": "YES",
        }

        debug = dict(shared)
        debug.update({
            "DEBUG_INFORMATION_FORMAT": "dwarf",
            "ENABLE_TESTABILITY": "YES",
            "GCC_DYNAMIC_NO_PIC": "NO",
            "GCC_OPTIMIZATION_LEVEL": "0",
            "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
            "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
            "ONLY_ACTIVE_ARCH": "YES",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        })

        release = dict(shared)
        release.update({
            "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
            "ENABLE_NS_ASSERTIONS": "NO",
            "MTL_ENABLE_DEBUG_INFO": "NO",
            "SWIFT_COMPILATION_MODE": "wholemodule",
            "VALIDATE_PRODUCT": "YES",
        })

        app = {
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "CODE_SIGN_ENTITLEMENTS": "App/Stickies-iOS.entitlements",
            "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]": "App/Stickies-macOS.entitlements",
            "COMBINE_HIDPI_IMAGES": "YES",
            "ENABLE_HARDENED_RUNTIME": "YES",
            "ENABLE_PREVIEWS": "YES",
            "GENERATE_INFOPLIST_FILE": "NO",
            "INFOPLIST_FILE": "App/Info.plist",
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
            "LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]": ["$(inherited)", "@executable_path/../Frameworks"],
            "PRODUCT_BUNDLE_IDENTIFIER": "$(APP_BUNDLE_ID)",
            "PRODUCT_NAME": "$(TARGET_NAME)",
        }

        widget = {
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME": "WidgetBackground",
            "CODE_SIGN_ENTITLEMENTS": "Widgets/StickiesWidgets-iOS.entitlements",
            "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]": "Widgets/StickiesWidgets-macOS.entitlements",
            "ENABLE_HARDENED_RUNTIME": "YES",
            "ENABLE_PREVIEWS": "YES",
            "GENERATE_INFOPLIST_FILE": "NO",
            "INFOPLIST_FILE": "Widgets/Info.plist",
            "LD_RUNPATH_SEARCH_PATHS": [
                "$(inherited)",
                "@executable_path/Frameworks",
                "@executable_path/../../Frameworks",
            ],
            "LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]": [
                "$(inherited)",
                "@executable_path/../Frameworks",
                "@executable_path/../../../../Frameworks",
            ],
            "PRODUCT_BUNDLE_IDENTIFIER": "$(WIDGET_BUNDLE_ID)",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SKIP_INSTALL": "YES",
        }

        entries = []
        lists = []

        def add(owner, name, settings, use_xcconfig):
            config_id = oid("config", owner, name)
            lines = ["\t\t%s /* %s */ = {" % (config_id, name)]
            lines.append("\t\t\tisa = XCBuildConfiguration;")
            if use_xcconfig:
                lines.append(
                    "\t\t\tbaseConfigurationReference = %s /* Base.xcconfig */;" % self.xcconfig_ref
                )
            lines.append("\t\t\tbuildSettings = {")
            lines.extend(settings_lines(settings, 4))
            lines.append("\t\t\t};")
            lines.append("\t\t\tname = %s;" % name)
            lines.append("\t\t};")
            entries.append("\n".join(lines))
            return config_id

        def add_list(owner, label, default, config_ids):
            list_id = oid("configlist", owner)
            lines = ["\t\t%s /* Build configuration list for %s */ = {" % (list_id, label)]
            lines.append("\t\t\tisa = XCConfigurationList;")
            lines.append("\t\t\tbuildConfigurations = (")
            for name, config_id in config_ids:
                lines.append("\t\t\t\t%s /* %s */," % (config_id, name))
            lines.append("\t\t\t);")
            lines.append("\t\t\tdefaultConfigurationIsVisible = 0;")
            lines.append("\t\t\tdefaultConfigurationName = %s;" % default)
            lines.append("\t\t};")
            lists.append("\n".join(lines))

        project_configs = [
            ("Debug", add("PROJECT", "Debug", debug, True)),
            ("Release", add("PROJECT", "Release", release, True)),
        ]
        add_list("PROJECT", 'PBXProject "%s"' % PROJECT_NAME, "Release", project_configs)

        for name, settings in ((APP_TARGET, app), (WIDGET_TARGET, widget)):
            configs = [
                ("Debug", add(name, "Debug", settings, False)),
                ("Release", add(name, "Release", settings, False)),
            ]
            add_list(name, 'PBXNativeTarget "%s"' % name, "Release", configs)

        return self.section("XCBuildConfiguration", entries) + self.section("XCConfigurationList", lists)

    # -- assembly ----------------------------------------------------------

    @staticmethod
    def section(name, entries):
        if not entries:
            return ""
        return "\n/* Begin %s section */\n%s\n/* End %s section */\n" % (
            name,
            "\n".join(entries),
            name,
        )

    def render(self):
        phase_ids, phase_text = self.phases()
        body = "".join([
            self.build_file_section(),
            self.target_section(phase_ids),
            self.file_reference_section(),
            self.group_section(),
            phase_text,
            self.project_object(),
            self.configurations(),
        ])
        return "".join([
            "// !$*UTF8*$!\n",
            "{\n",
            "\tarchiveVersion = 1;\n",
            "\tclasses = {\n",
            "\t};\n",
            "\tobjectVersion = 56;\n",
            "\tobjects = {\n",
            body,
            "\t};\n",
            "\trootObject = %s /* Project object */;\n" % self.project_id,
            "}\n",
        ])


SCHEME = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1540"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app_target}"
               BuildableName = "Stickies.app"
               BlueprintName = "Stickies"
               ReferencedContainer = "container:Stickies.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target}"
            BuildableName = "Stickies.app"
            BlueprintName = "Stickies"
            ReferencedContainer = "container:Stickies.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target}"
            BuildableName = "Stickies.app"
            BlueprintName = "Stickies"
            ReferencedContainer = "container:Stickies.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""

WORKSPACE = """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
"""


def main():
    project = Project()

    if os.path.isdir(PROJECT_DIR):
        shutil.rmtree(PROJECT_DIR)
    os.makedirs(os.path.join(PROJECT_DIR, "xcshareddata", "xcschemes"))
    os.makedirs(os.path.join(PROJECT_DIR, "project.xcworkspace", "xcshareddata"))

    with open(os.path.join(PROJECT_DIR, "project.pbxproj"), "w") as handle:
        handle.write(project.render())

    with open(os.path.join(PROJECT_DIR, "xcshareddata", "xcschemes", "Stickies.xcscheme"), "w") as handle:
        handle.write(SCHEME.replace("{app_target}", project.app_target))

    with open(os.path.join(PROJECT_DIR, "project.xcworkspace", "contents.xcworkspacedata"), "w") as handle:
        handle.write(WORKSPACE)

    with open(
        os.path.join(PROJECT_DIR, "project.xcworkspace", "xcshareddata", "IDEWorkspaceChecks.plist"), "w"
    ) as handle:
        handle.write(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
            '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
            '<plist version="1.0">\n<dict>\n'
            "\t<key>IDEDidComputeMac32BitWarning</key>\n\t<true/>\n"
            "</dict>\n</plist>\n"
        )

    print("wrote %s" % os.path.relpath(PROJECT_DIR, ROOT))
    print("  %d shared sources" % len(project.shared_sources))
    print("  %d app sources" % len(project.app_sources))
    print("  %d widget sources" % len(project.widget_sources))


if __name__ == "__main__":
    main()
