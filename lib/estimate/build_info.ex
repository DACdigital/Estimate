defmodule Estimate.BuildInfo do
  @moduledoc """
  Build metadata for the running release.

  `GIT_SHA` is captured at compile time (Docker builder-stage `ARG`/`ENV`;
  `.dockerignore` excludes `.git`, so the image cannot self-derive it),
  can be overridden by the runtime env, and falls back to the local git
  checkout in dev/test. The compile-time value goes stale in a long-lived
  dev session until recompile — acceptable for a deploy marker.
  """

  @compile_time_sha System.get_env("GIT_SHA")

  @local_sha (case @compile_time_sha do
                sha when sha in [nil, ""] ->
                  try do
                    case System.cmd("git", ["rev-parse", "--short=7", "HEAD"],
                           stderr_to_stdout: true
                         ) do
                      {sha, 0} -> String.trim(sha)
                      _ -> nil
                    end
                  rescue
                    ErlangError -> nil
                  end

                _ ->
                  nil
              end)

  @doc "Short git revision of this build, or `nil` when unknown."
  def git_sha do
    presence(@compile_time_sha) || presence(System.get_env("GIT_SHA")) || @local_sha
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(value), do: value
end
