# Copyright 2026, Pulumi Corporation.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# frozen_string_literal: true

module Pulumi
  # A single blob of data that can be passed to a resource -- a file, a literal string, or
  # something fetched from a URI.
  #
  # Assets are opaque to the SDK: it hands the reference to the engine, which reads the
  # content when a provider needs it. That is why {FileAsset} holds a path rather than the
  # file's bytes.
  #
  # The names are flat (FileAsset, not Asset::File) to match every other Pulumi SDK, and
  # because nesting them under Asset would put a class named `String` in scope inside this
  # namespace and shadow Ruby's own.
  class Asset
    # Abstract: exists so `case value when Asset` dispatch works in the serializer.
  end

  # An asset backed by a file on disk.
  class FileAsset < Asset
    # @return [String]
    attr_reader :path

    def initialize(path)
      super()
      @path = path
    end
  end

  # An asset whose content is given inline.
  class StringAsset < Asset
    # @return [String]
    attr_reader :text

    def initialize(text)
      super()
      @text = text
    end
  end

  # An asset the engine fetches from a URI (file://, http://, https://).
  class RemoteAsset < Asset
    # @return [String]
    attr_reader :uri

    def initialize(uri)
      super()
      @uri = uri
    end
  end

  # A collection of {Asset}s -- a directory, an archive file, or an explicit map.
  class Archive
    # Abstract: exists so `case value when Archive` dispatch works in the serializer.
  end

  # An archive backed by a directory or archive file on disk.
  class FileArchive < Archive
    # @return [String]
    attr_reader :path

    def initialize(path)
      super()
      @path = path
    end
  end

  # An archive the engine fetches from a URI.
  class RemoteArchive < Archive
    # @return [String]
    attr_reader :uri

    def initialize(uri)
      super()
      @uri = uri
    end
  end

  # An archive assembled from named assets and nested archives.
  #
  #   Pulumi::AssetArchive.new(
  #     "index.html" => Pulumi::FileAsset.new("./index.html"),
  #     "static"     => Pulumi::FileArchive.new("./static")
  #   )
  class AssetArchive < Archive
    # @return [Hash{String => Asset, Archive}]
    attr_reader :assets

    def initialize(assets)
      super()
      @assets = assets
    end
  end
end
