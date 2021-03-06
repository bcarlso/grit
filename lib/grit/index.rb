module Grit

  class Index
    # Public: Gets/Sets the Grit::Repo to which this index belongs.
    attr_accessor :repo

    # Public: Gets/Sets the Hash tree map that holds the changes to be made
    # in the next commit.
    attr_accessor :tree

    # Public: Gets/Sets the Grit::Tree object representing the tree upon
    # which the next commit will be based.
    attr_accessor :current_tree

    # Initialize a new Index object.
    #
    # repo - The Grit::Repo to which the index belongs.
    #
    # Returns the newly initialized Grit::Index.
    def initialize(repo)
      self.repo = repo
      self.tree = {}
      self.current_tree = nil
    end

    # Public: Add a file to the index.
    #
    # path - The String file path including filename (no slash prefix).
    # data - The String binary contents of the file.
    #
    # Returns nothing.
    def add(path, data)
      path = path.split('/')
      filename = path.pop

      current = self.tree

      path.each do |dir|
        current[dir] ||= {}
        node = current[dir]
        current = node
      end

      current[filename] = data
    end

    # Public: Delete the given file from the index.
    #
    # path - The String file path including filename (no slash prefix).
    #
    # Returns nothing.
    def delete(path)
      add(path, false)
    end

    # Public: Read the contents of the given Tree into the index to use as a
    # starting point for the index.
    #
    # tree - The String branch/tag/sha of the Git tree object.
    #
    # Returns nothing.
    def read_tree(tree)
      self.current_tree = self.repo.tree(tree)
    end

    # Public: Commit the contents of the index
    #
    # message   - The String commit message.
    # parents   - Array of String commit SHA1s or Grit::Commit objects to
    #             attach this commit to to form a new head (default: nil).
    # actor     - The Grit::Actor details of the user making the commit
    #             (default: nil).
    # last_tree - The String SHA1 of a tree to compare with in order to avoid
    #             making empty commits (default: nil).
    # head      - The String branch name to write this head to
    #             (default: "master").
    #
    # Returns a String of the SHA1 of the new commit.
    def commit(message, parents = nil, actor = nil, last_tree = nil, head = 'master')
      tree_sha1 = write_tree(self.tree, self.current_tree)

      # don't write identical commits
      return false if tree_sha1 == last_tree

      contents = []
      contents << ['tree', tree_sha1].join(' ')
      parents.each do |p|
        contents << ['parent', p].join(' ')
      end if parents

      if actor
        name  = actor.name
        email = actor.email
      else
        config = Config.new(self.repo)
        name   = config['user.name']
        email  = config['user.email']
      end

      author_string = "#{name} <#{email}> #{Time.now.to_i} -0700" # !! TODO : gotta fix this
      contents << ['author', author_string].join(' ')
      contents << ['committer', author_string].join(' ')
      contents << ''
      contents << message

      commit_sha1 = self.repo.git.put_raw_object(contents.join("\n"), 'commit')

      self.repo.update_ref(head, commit_sha1)
    end

    # Recursively write a tree to the index.
    #
    # tree -     The Hash tree map:
    #            key - The String directory or filename.
    #            val - The Hash submap or the String contents of the file.
    # now_tree - The Grit::Tree representing the a previous tree upon which
    #            this tree will be based (default: nil).
    #
    # Returns the String SHA1 String of the tree.
    def write_tree(tree, now_tree = nil)
      tree_contents = {}

      # fill in original tree
      now_tree.contents.each do |obj|
        sha = [obj.id].pack("H*")
        k = obj.name
        k += '/' if (obj.class == Grit::Tree)
        tree_contents[k] = "%s %s\0%s" % [obj.mode.to_s, obj.name, sha]
      end if now_tree

      # overwrite with new tree contents
      tree.each do |k, v|
        case v
          when String
            sha = write_blob(v)
            sha = [sha].pack("H*")
            str = "%s %s\0%s" % ['100644', k, sha]
            tree_contents[k] = str
          when Hash
            ctree = now_tree/k if now_tree
            sha = write_tree(v, ctree)
            sha = [sha].pack("H*")
            str = "%s %s\0%s" % ['40000', k, sha]
            tree_contents[k + '/'] = str
          when false
            tree_contents.delete(k)
        end
      end

      tr = tree_contents.sort.map { |k, v| v }.join('')
      self.repo.git.put_raw_object(tr, 'tree')
    end

    # Write a blob to the index.
    #
    # data - The String data to write.
    #
    # Returns the String SHA1 of the new blob.
    def write_blob(data)
      self.repo.git.put_raw_object(data, 'blob')
    end
  end # Index

end # Grit
