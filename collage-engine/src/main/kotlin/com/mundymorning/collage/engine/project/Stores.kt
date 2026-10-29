package com.mundymorning.collage.engine.project

import android.graphics.Bitmap
import org.json.JSONArray
import java.io.File

data class ProjectSummary(val id: String, val name: String, val updatedAt: Long, val mode: ProjectMode, val photoCount: Int, val thumb: File?)

/**
 * File-based, app-private storage: `projects/<id>.json`, `thumbs/<id>.jpg`, `media/<photo files>`.
 * Nothing leaves this directory unless the user exports or shares.
 */
class ProjectStore(private val root: File) {
    val mediaDir = File(root, "media").apply { mkdirs() }
    private val projectsDir = File(root, "projects").apply { mkdirs() }
    private val thumbsDir = File(root, "thumbs").apply { mkdirs() }

    private fun file(id: String) = File(projectsDir, "$id.json")
    fun thumbFile(id: String) = File(thumbsDir, "$id.jpg")

    /** Atomic write: a crash mid-save can never corrupt the previous version. */
    fun save(p: CollageProject) {
        val tmp = File(projectsDir, "${p.id}.json.tmp")
        tmp.writeText(ProjectJson.serialize(p))
        val dest = file(p.id)
        if (!tmp.renameTo(dest)) { dest.delete(); tmp.renameTo(dest) }
    }

    fun load(id: String): CollageProject? = try {
        file(id).takeIf { it.exists() }?.let { ProjectJson.parseProject(it.readText()) }
    } catch (t: Exception) {
        null
    }

    fun saveThumb(id: String, bitmap: Bitmap) {
        thumbFile(id).outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 85, it) }
    }

    /** Newest first. Unreadable files are skipped, never crash the home screen. */
    fun list(): List<ProjectSummary> = (projectsDir.listFiles { f -> f.name.endsWith(".json") } ?: emptyArray())
        .mapNotNull { f ->
            try {
                val p = ProjectJson.parseProject(f.readText())
                ProjectSummary(p.id, p.name, p.updatedAt, p.mode, p.photoCount, thumbFile(p.id).takeIf { it.exists() })
            } catch (t: Exception) {
                null
            }
        }
        .sortedByDescending { it.updatedAt }

    fun delete(id: String) {
        file(id).delete(); thumbFile(id).delete()
        collectGarbage()
    }

    /** Remove imported photos no remaining project refers to. */
    fun collectGarbage() {
        val used = HashSet<String>()
        projectsDir.listFiles { f -> f.name.endsWith(".json") }?.forEach { f ->
            try { ProjectJson.parseProject(f.readText()).cells.forEach { c -> c.photo?.let { used += it.file } } }
            catch (t: Exception) { /* keep everything if something is unreadable */ return }
        }
        mediaDir.listFiles()?.forEach { if (it.name !in used && !it.name.endsWith(".tmp")) it.delete() }
    }
}

class TemplateStore(root: File) {
    private val file = File(root, "templates.json")

    fun list(): List<SavedTemplate> = try {
        if (!file.exists()) emptyList() else {
            val a = JSONArray(file.readText())
            List(a.length()) { ProjectJson.parseTemplate(a.getJSONObject(it)) }
        }
    } catch (t: Exception) {
        emptyList()
    }

    fun add(t: SavedTemplate) = write(list().filter { it.id != t.id } + t)
    fun delete(id: String) = write(list().filter { it.id != id })

    private fun write(all: List<SavedTemplate>) {
        val a = JSONArray().also { arr -> all.forEach { arr.put(ProjectJson.toJson(it)) } }
        val tmp = File(file.parentFile, "templates.json.tmp")
        tmp.writeText(a.toString())
        if (!tmp.renameTo(file)) { file.delete(); tmp.renameTo(file) }
    }
}
